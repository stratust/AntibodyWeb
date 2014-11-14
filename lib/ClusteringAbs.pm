package ClusteringAbs;
    use Moose;
    use Method::Signatures;
    use AntibodyWeb::Model::AntibodyDB::External;
    use feature qw(say);
    use MooseX::FileAttribute;
    use String::Cluster::Hobohm;
    use Storable qw(dclone);
    #use Data::Printer class => { expand => 'all' };
    use Data::Printer;
    use namespace::autoclean;

    my $obj = AntibodyWeb::Model::AntibodyDB::External->new();
    our $schema = $obj->schema;
    our $kiokudb = $obj->kiokudb;
    

    has 'cdr3_similarity' => (
        is          => 'rw',
        isa         => 'Num',
        required    => 1,
        default     => 0.7
    );

    has 'use_light' => (
        is  => 'rw',
        isa => 'Bool',
        default => 0,
    );

    method get_combo_from_db ( Int $assay_id, Int $clustering_type) {
        my %combo;
        my $sequence_rs;
        #$combo{id}{'H|L|L'};
        my $scope = $kiokudb->new_scope;


        if ( $clustering_type == 1 ) {
            $sequence_rs = $schema->resultset('PutativeAnnotation')->search( 
                { 
                    assay_id => $assay_id,
                    chain_type_name => { "like" => '%heavy%' },
                }, 
                { 
                    join => [
                        'chain_type',
                        { 'sequence_rel' => 'file' }
                    ], 
                } 
            );
            my $i = 1;
            while ( my $s = $sequence_rs->next ) {
                next unless $s->putative_annotation_is_complete;
                $combo{$i}{H} = $kiokudb->lookup( $s->object_id );
                $i++;
            }
        }
        elsif ( $clustering_type == 2 ) {

        }
        elsif ( $clustering_type == 3 ) {
            $sequence_rs = $schema->resultset('PutativeAnnotation')->search( 
                { 
                    heavy_file_id => { '-NOT' => undef } 
                },
                { 
                    join => { 
                        'sequence_rel' => 'sequence_has_sequence_heavy_files' 
                    }, 
                } 
            );

            my $i = 1;
            while ( my $s = $sequence_rs->next ) {
                my $heavy_seq = $s->sequence_rel;

                #say $heavy_seq->get_column('sequence_name');
                my $heavy_has_light = $heavy_seq->sequence_has_sequence_heavy_files->first;
                my $light_seq       = $heavy_has_light->light_file;

                #say join " => ",($heavy_seq->get_column('sequence_name'),$light_seq->get_column('sequence_name'));
                my $heavy_putative = $heavy_seq->putative_annotations->first;
                my $light_putative = $light_seq->putative_annotations->first;
                $combo{$i}{H} = $kiokudb->lookup( $heavy_putative->object_id );
                $combo{$i}{L}{kappa} = $kiokudb->lookup( $light_putative->object_id );
                $i++;
            }

        }
        return \%combo;
    }


    method _filter_chain (Bio::Moose::IgBlast $chain) {
        my $key = 0;
        # Filter Heavy and Light chain without alignments with germline
        if ( $chain->rearrangement_summary ) {
            my $r = $chain->rearrangement_summary;

            # Getting (VDJ info)
=cut
            if (
                ( $r->top_V_match && $r->top_J_match )
                && (   $r->top_V_match ne 'N/A'
                    && $r->top_J_match ne 'N/A' )
              )
            {
=cut

            if (   ( $r->top_V_match )
                && ( $r->top_V_match ne 'N/A' ) )
            {

                # Getting Bio::Moose::IgBlast::RenderedAlignment object
                my $aln = $chain->rendered_alignment;
                if ($aln) {
                    if ( $chain->infer_CDR3_nt_length ne 'N/A' ) {
                        my @V = split ",", $r->top_V_match;
                        #my @J = split ",", $r->top_J_match;
                        #$key = "($V[0]!$J[0])";
                        $key = "($V[0])";
                    }
                }
            }
        }
        return $key;
    }


    method filter_abs ( HashRef $combo) {
        my %to_cluster;
        my %heavy_only;
        my %light_only;
        my %trash;
        my %count;

        foreach my $well ( sort { $a cmp $b } keys %{$combo} ) {
            my $chains = $combo->{$well};
            my $heavy  = $chains->{H};
            my $lambda = $chains->{L}{lambda};
            my $kappa  = $chains->{L}{kappa};

            my ( $key_heavy, $key_lambda, $key_kappa );
            $key_heavy = $self->_filter_chain($heavy) if $heavy;
            $key_lambda = $self->_filter_chain($lambda) if $lambda;
            $key_kappa = $self->_filter_chain($kappa) if $kappa;

            # skip sequences without heavy or light chain
            if ( $key_heavy && $key_kappa ) {
                my $key = "$key_heavy|$key_kappa";
                #my $key = "$key_heavy";
                $to_cluster{$key}{$well} = $combo->{$well};
                $count{to_cluster}++;
            }
            elsif ($key_heavy) {
#            if ($key_heavy) {
                $heavy_only{$key_heavy}{$well} = $combo->{$well};
                $count{heavy_only}++;
            }
            elsif ($key_lambda && $key_kappa) {
                my $key = "$key_lambda|$key_kappa";
                $light_only{$key}{$well} = $combo->{$well};
                $count{lambda_and_kappa_only}++;
            }
            elsif ($key_lambda && $key_kappa) {
                my $key = "$key_lambda|$key_kappa";
                $light_only{$key}{$well} = $combo->{$well};
                $count{lambda_and_kappa_only}++;
            }
            elsif ($key_lambda) {
                $light_only{$key_lambda}{$well} = $combo->{$well};
                $count{lambda_only}++;
            }
            elsif ($key_kappa) {
                $light_only{$key_kappa}{$well} = $combo->{$well};
                $count{kappa_only}++;
            }
            else {
                $trash{$well} = $combo->{$well};
                $count{trash}++;
            }

        }
        
        #p %count;
        
        return {
            to_cluster => \%to_cluster,
            heavy_only => \%heavy_only,
            light_only => \%light_only,
            trash      => \%trash
        };
    }


    method clustering_both (HashRef $to_cluster) {
        my %clone;

        my $clusterer = String::Cluster::Hobohm->new( similarity => $self->cdr3_similarity );

        # Looking for CDR3
        foreach my $vj_key ( sort { $a cmp $b } keys %{$to_cluster} ) {
            my %aux;

            foreach
              my $well ( sort { $a cmp $b } keys %{ $to_cluster->{$vj_key} } )
            {
                my $h_cdr3 =
                  $to_cluster->{$vj_key}->{$well}->{H}
                  ->infer_CDR3_nt;
                my $l_cdr3 =
                  $to_cluster->{$vj_key}->{$well}->{L}->{kappa}
                  ->infer_CDR3_nt;

                $h_cdr3 =~ s/\|//g;
                $l_cdr3 =~ s/\|//g;

                my $cdr3_key = "($h_cdr3!$l_cdr3)";

                push @{ $aux{$cdr3_key} }, $to_cluster->{$vj_key}->{$well};

            }

            my @CDR3s  = keys %aux;
            my $groups = $clusterer->cluster( \@CDR3s );

            foreach my $g ( @{$groups} ) {
                my $cdr3 = ${ $g->[0] };
                foreach my $el ( @{$g} ) {
                    push @{ $clone{$vj_key}{$cdr3} }, @{ $aux{ ${$el} } };
                }
            }
        }
        return \%clone;

    }


    method _print_clones ($clone, $chain_type) {
        my $counter = 0;
        foreach my $vj_key ( sort { $a cmp $b } keys %{$clone} ) {
            foreach
              my $cdr3_key ( sort { $a cmp $b } keys %{ $clone->{$vj_key} } )
            {
                if ( scalar @{ $clone->{$vj_key}->{$cdr3_key} } > 0 ) {
                    $counter += scalar @{ $clone->{$vj_key}->{$cdr3_key} };

#my $i;
#say $k. $c;
#say join "\t", ( $i++, $_->[0]->{$chain_type}->query_id ) foreach @{ $clone->{$k}->{$c} };
                }
            }
        }
        #say "total of seqs $chain_type:" . $counter;
    }


    method clustering_single (HashRef $to_cluster, Str $chain_type) {
        my %clone;

        my $clusterer = String::Cluster::Hobohm->new( similarity => $self->cdr3_similarity );
        my $i = 0;

        # Looking for CDR3 in each VJ cluster
        my $sum   = 0;
        my $debug = 0;

        foreach my $vj_key ( sort { $a cmp $b } keys %{$to_cluster} ) {
            my %aux;

            # Group by CDR3
            foreach
              my $well ( sort { $a cmp $b } keys %{ $to_cluster->{$vj_key} } )
            {
                $i++;
                my $cdr3;
                if ( $chain_type =~ /H/ ){
                    $cdr3 = $to_cluster->{$vj_key}->{$well}->{H}
                  ->infer_CDR3_nt;
                }
                if ($chain_type =~ /L/){
                    my $lambda = $to_cluster->{$vj_key}->{$well}->{L}{lambda};
                    my $kappa = $to_cluster->{$vj_key}->{$well}->{L}{kappa};

                    if ($lambda){
                        $cdr3 .= $lambda->infer_CDR3_nt;   
                    }
                    if ($kappa){
                        $cdr3 .= $kappa->infer_CDR3_nt;   
                    }
                }
                #else {
                #    die "No H or L chain specified";
                # }

                $cdr3 =~ s/\|//g;
                my $cdr3_key = $cdr3;
                
                push @{ $aux{$cdr3_key} }, $to_cluster->{$vj_key}->{$well};
                delete $to_cluster->{$vj_key}->{$well};
            }

            $debug += scalar @{ $aux{$_} } foreach keys %aux;
            my @CDR3s  = sort {$a cmp $b } keys %aux;
            my $groups = $clusterer->cluster( \@CDR3s );

            foreach my $g ( @{$groups} ) {
                my $cdr3 = ${ $g->[0] };
                foreach my $el ( @{$g} ) {
                    push @{ $clone{$vj_key}{$cdr3} }, @{ $aux{ ${$el} } };
                    delete $aux{ ${$el} };
                }
                $sum += scalar @{ $clone{$vj_key}{$cdr3} };
            }
        }
        #say "Sum $chain_type: $sum";
        #say "Debug: $debug";

        $self->_print_clones( \%clone, $chain_type );
        #say "Well $chain_type: $i";
        return \%clone;
    }


    method combine_clones (HashRef :$both_clones, HashRef :$heavy_clones, HashRef :$light_clones) {

        my $clusterer = String::Cluster::Hobohm->new( similarity => $self->cdr3_similarity );
        if ($both_clones){
        foreach my $vj_k ( sort { $a cmp $b } keys %{$both_clones} ) {
            #say $vj_k;
            my ( $Hvj, $Lvj ) = split /\|/, $vj_k;
            my $heavy_only = $heavy_clones->{$Hvj};
            my $light_only = $light_clones->{$Lvj};

            foreach my $cdr3_both ( sort { $a cmp $b }
                keys %{ $both_clones->{$vj_k} } )
            {
                my ( $h_cdr3, $l_cdr3 );
                ( $h_cdr3, $l_cdr3 ) = ( $1, $2 )
                  if $cdr3_both =~ /\((.*)\!.(.*)\)/;

                if ($heavy_only) {

                    # heavy
                    my @cdr3_heavy_only = keys %{$heavy_only};

                    # clustering
                    push @cdr3_heavy_only, $h_cdr3;
                    my $h_groups = $clusterer->cluster( \@cdr3_heavy_only );

                    foreach my $g ( @{$h_groups} ) {
                        my %hash = map { ${$_} => 1 } @{$g};

                        if ( $hash{$h_cdr3} ) {

                            foreach my $k ( keys %hash ) {

                                if ( $heavy_only->{$k} ) {
                                    push @{ $both_clones->{$vj_k}->{$cdr3_both}
                                      },
                                      @{ $heavy_only->{$k} };
                                    delete $heavy_only->{$k};
                                }

                            }
                        }
                    }

                }

                if ($light_only) {

                    # light
                    my @cdr3_light_only = keys %{$light_only};

                    # clustering
                    push @cdr3_light_only, $l_cdr3;
                    my $l_groups = $clusterer->cluster( \@cdr3_light_only );

                    foreach my $g ( @{$l_groups} ) {
                        my %hash = map { ${$_} => 1 } @{$g};

                        if ( $hash{$l_cdr3} ) {

                            foreach my $k ( keys %hash ) {

                                if ( $light_only->{$k} ) {
                                    push @{ $both_clones->{$vj_k}->{$cdr3_both}
                                      },
                                      @{ $light_only->{$k} };
                                    delete $light_only->{$k};

                                }
                            }
                        }

                    }
                }
            }
        }
        }
        return {
            both_chains => $both_clones,
            heavy_only  => $heavy_clones,
            light_only  => $light_clones
        };
    }

    method output_template (HashRef $all_clusters, HashRef $trash) {
        my @ROWS    = (qw/best_V best_D best_J/);
        my @regions = (qw/ FWR1 CDR1 FWR2 CDR2 FWR3 /);

        #my @col_header = (qw/query_id/, @ROWS ,qw/CDR3_seq CDR3_length FWR1 gaps mismatches CDR1 gaps mismatches FWR2 gaps mismatches CDR2 gaps mismatches FRW3 gaps mismatches/);
        my @col_header = (
            qw/query_id productive stop-codon/, @ROWS,
           qw/CDR3_nt CDR3_nt_length CDR3_aa CDR3_aa_length FWR1 gaps mismatches aa_mismatches aa_insertions aa_deletions FWR1_aa CDR1 gaps mismatches aa_mismatches aa_insertions aa_deletions CDR1_aa FWR2 gaps mismatches aa_mismatches aa_insertions aa_deletions FWR2_aa CDR2 gaps mismatches aa_mismatches aa_insertions aa_deletions CDR2_aa FRW3 gaps mismatches aa_mismatches aa_insertions aa_deletions FRW3_aa total_nt_mismatches nt_sequence total_aa_mismatches aa_sequence nt_matches_seq/

        );
        
        my @final_header;

        foreach my $chain (qw/heavy lambda kappa/) {
            push @final_header, $_.'_'.$chain foreach @col_header;
        }

        @final_header = ( 'clone_id','n_sequences',@final_header);

        my %aux;
        my %aux_order;
        my %filtered; # remove sequences with stop codon from analysis
        my $copy_all_clusters =  dclone($all_clusters);
        my %aux_copy;

        foreach my $type ( sort { $a cmp $b }  keys %{$all_clusters} ) {
            my $clone = $all_clusters->{$type};
            say $type;
            foreach my $vj_key ( sort { $a cmp $b } keys %{$clone} ) {
                foreach my $cdr3_key (
                    sort { $a cmp $b }
                    keys %{ $clone->{$vj_key} }
                    )
                {
                    $aux{$type}{ $vj_key . '_' . $cdr3_key } = scalar @{ $clone->{$vj_key}->{$cdr3_key} };
                    
                    my $z=0;
                    foreach my $well (@{ $clone->{$vj_key}->{$cdr3_key} }) {

                        if ( $well->{H}){

                            if ( $well->{H}->rearrangement_summary ){

                                my $has_stop_codon = $well->{H}->rearrangement_summary->stop_codon;
                                
                                if ( $has_stop_codon =~ /Yes/i){
                                    splice (@{$copy_all_clusters->{$type}->{$vj_key}->{$cdr3_key}},$z,1)                         
                                }else{
                                    $z++;
                                }
                            }
                        }
                    }
                    $aux_copy{$type}{ $vj_key . '_' . $cdr3_key } = scalar @{ $copy_all_clusters->{$type}->{$vj_key}->{$cdr3_key} };
                }
            }
            my @order =  sort { $aux{$type}{$b} <=> $aux{$type}{$a} || $a cmp $b } keys %{$aux{$type}};
            $aux_order{$type} = \@order;
        }
        
        # Remove light chains of copy
        delete $copy_all_clusters->{light_only};
          # Set color
        my @colors = (
            qw [FF0000
                FF8000
                FFFF00
                80FF00
                00FF00
                00FF80
                00FFFF
                0080FF
                0000FF
                7F00FF
                FF00FF
                FF007F
                808080
                ]);


        my @colors_copy = @colors;

        # Getting information about Regions
        #$self->get_jitter_plot_info($copy_all_clusters->{heavy_only},$aux{heavy_only},$aux_order{heavy_only}, \@colors_copy);




        my @clones;
        my @values;
        my @values_copy;
        my $single = 0;
        my $single_copy = 0;
        my $j = 1;


        foreach my $key (@{$aux_order{heavy_only}}) {
           my $count = $aux{heavy_only}{$key};
           my $count_copy = $aux_copy{heavy_only}{$key};
 
           if ($count > 1){
               push @clones, $j++;
               push @values, $count;
               push @values_copy, $count_copy;
           }
           else{
               $single++;
                if ($count_copy == 1){
                    $single_copy++;
                }
           }

        }
        push @clones, $j if $single;
        push @values, $single if $single;
        push @values_copy, $single_copy if $single_copy;

        my $data = [
            ['clone_id',@clones],
            ['count', @values],
            ['count_filtered', @values_copy],
        ];
        

       # Start modify palette from this index
        my $index=0;

        # Add a few parameters
        return {
            all_clusters    => $all_clusters,
            filtered_all_clusters    => $copy_all_clusters,
            aux_order       => \%aux_order,
            aux             => \%aux,
            worksheet_name  => 'test',
            col_header      => \@final_header,
            trash           => $trash,
            colors       => \@colors_copy,
            max_color_index => ( $index + $#colors ),

        };

    }


    # Only for heavy_chain

    method run_clustering( Int $assay_id, Int $clustering_type ) {
        my $combo;
        $combo = $self->get_combo_from_db( $assay_id, $clustering_type );

        my $groups = $self->filter_abs($combo);
        my $light_clones = $self->clustering_single( $groups->{light_only}, 'L' );

        my $all;
        if ( $self->use_light ) {
            my $both_clones = $self->clustering_both( $groups->{to_cluster}, );

            #$self->_print_clones( $both_clones, 'H' );

            my $heavy_clones = $self->clustering_single( $groups->{heavy_only}, 'H' );

            #        if (! $self->lotta) {

            $all = $self->combine_clones(
                both_clones  => $both_clones,
                heavy_clones => $heavy_clones,
                light_clones => $light_clones
            );

            #}
        }
        else {
            my %hash = ( %{ $groups->{to_cluster} }, %{ $groups->{heavy_only} } );
            my $heavy_clones = $self->clustering_single( \%hash, 'H' );
            $all = {
                heavy_only => $heavy_clones,
                light_only => $light_clones,
                }

        }

        return $all;

    }


__PACKAGE__->meta->make_immutable;
    
1;
