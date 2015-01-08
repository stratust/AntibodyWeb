package ClusteringAbsDB;
    use Moose;
    use Method::Signatures;
    use AntibodyWeb::Model::AntibodyDB::External;
    use feature qw(say);
    use MooseX::FileAttribute;
    use String::Cluster::Hobohm;
    use Storable qw(dclone);
    #use Data::Printer class => { expand => 'all' };
    use Data::Printer;
    use Bio::Seq;
    use Bio::SeqIO;
    use Bio::Tools::Run::Alignment::Clustalw;
    use Bio::Moose::IgBlastIO;
    use Bio::Moose::Run::IgBlastN;
    use namespace::autoclean;

    my $obj = AntibodyWeb::Model::AntibodyDB::External->new();
    our $schema = $obj->schema;
    our $kiokudb = $obj->kiokudb;
    
    has_file 'output_file' => (
        required      => 0,
        documentation => q[Output file in xlsx format],
    );
 
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

    method get_v_cluster_from_db ( Int $assay_id, Int $clustering_type, Int|Undef :$igblast_param_id ) {
        my %v_cluster;
        my $sequence_rs;
        my $scope = $kiokudb->new_scope;

        if ( $clustering_type == 1 ) {
            $sequence_rs = $schema->resultset('PutativeAnnotation')->search( 
                { 
                    assay_id => $assay_id,
                    chain_type_name => { "like" => '%heavy%' },
                    putative_annotation_putative_cdr3 => { "!=" => 'N/A' },
                    igblast_param_id => $igblast_param_id,
                }, 
                { 
                    join => [
                        'chain_type',
                        { 'sequence_rel' => 'file' }
                    ],
                   order_by => [ 
                       { -asc => 'putative_annotation_best_v' },
                       { -asc => 'putative_annotation_putative_cdr3'} 
                   ],
                } 
            );
            my $i = 1;
            my $last;
            while ( my $s = $sequence_rs->next ) {
                next unless $s->putative_annotation_is_complete;
                push @{ $v_cluster{ $s->putative_annotation_best_v } }, $s;
                $i++;
            }
        }
        elsif ( $clustering_type == 2 ) {
            $sequence_rs = $schema->resultset('PutativeAnnotation')->search(
                {   assay_id => $assay_id,
                    '-or'    => [
                        chain_type_name => { "like" => '%kappa%' },
                        chain_type_name => { "like" => '%gamma%' },
                    ],
                    putative_annotation_putative_cdr3 => { "!=" => 'N/A' },
                },
                {   join     => [ 'chain_type', { 'sequence_rel' => 'file' } ],
                    order_by => [
                        { -asc => 'putative_annotation_best_v' },
                        { -asc => 'putative_annotation_putative_cdr3' }
                    ],
                }
            );
            my $i = 1;
            my $last;
            while ( my $s = $sequence_rs->next ) {
                next unless $s->putative_annotation_is_complete;
                push @{ $v_cluster{ $s->putative_annotation_best_v } }, $s;
                $i++;
            }

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

        }
        return \%v_cluster;
    }


    method get_cdr3_cluster_db ($v_cluster) {
        my %clone;

        my $clusterer = String::Cluster::Hobohm->new( similarity => $self->cdr3_similarity );
        my $i = 0;

        # Looking for CDR3 in each V cluster
        my $sum   = 0;

        foreach my $v_key ( sort { $a cmp $b } keys %{$v_cluster} ) {
            my %aux;

            # Group by CDR3
            foreach  my $row ( @{ $v_cluster->{$v_key} } ) {
                $i++;
                my $cdr3 = $row->putative_annotation_putative_cdr3;
                $cdr3 =~ s/\|//g;
                push @{ $aux{$cdr3} }, $row;
            }
            my @CDR3s  = sort {$a cmp $b } keys %aux;
            my $groups = $clusterer->cluster( \@CDR3s );

            foreach my $g ( @{$groups} ) {
                my $local_cdr3 = ${ $g->[0] };
                foreach my $el ( @{$g} ) {
                    push @{ $clone{$v_key.'_'.$local_cdr3} }, @{ $aux{ ${$el} } };
                    delete $aux{ ${$el} };
                }
            }
        }

        # sort by clone size
        my @sorted_clone;
        foreach my $key (sort { $#{$clone{$b}} <=> $#{$clone{$a}} } keys %clone) {
            push @sorted_clone, $clone{$key};
        }
        
  
        return \@sorted_clone;
    }


    method check_annotations_in_db(Int $assay_id, Int $clustering_type, Int $igblast_param_id, ArrayRef :$sequence_ids ) {

        my $chain;
        if ( $clustering_type == 1 ) {
            $chain = { chain_type_name => { "like" => '%heavy%' } };
        }
        elsif ( $clustering_type == 2 ) {
            $chain = {
                '-or' => [
                    chain_type_name => { "like" => '%kappa%' },
                    chain_type_name => { "like" => '%gamma%' },
                ]
            };
        }
 
        my $germline_rs  = $schema->resultset('PutativeAnnotation')->search(
            {
                assay_id                          => $assay_id,
                %{$chain},
                putative_annotation_is_germline => 1,
            },
            {
                join     => [ 'chain_type', { 'sequence_rel' => 'file' } ],
            }
        );
 
        my $annotated_rs = $schema->resultset('PutativeAnnotation')->search(
            {
                assay_id                        => $assay_id,
                igblast_param_id                => $igblast_param_id,
                putative_annotation_is_germline => 0,
            },
            {
                join => [ 'chain_type', { 'sequence_rel' => 'file' } ],
            }
        );

        if ($annotated_rs->count > 0){
            my @ids;
            while (my $annot = $annotated_rs->next){
                push @ids, $annot->putative_annotation_id;
            }
            $germline_rs = $germline_rs->search({ putative_annotation_id => {'-not_in' => \@ids} });
        }
        
        my @seq_ids;
        while (my $put = $germline_rs->next) {
            next if $put->igblast_param_id == $igblast_param_id;
            next if $put->sequence_id == 1126;
            push @seq_ids, $put->sequence_id ;    
        } 


        p @seq_ids;
        if (@seq_ids) {
            my $fasta = $self->create_fasta( \@seq_ids );

            #"Running Igblast";
            my ( $igblast_file, $organism_id ) =
              $self->run_igblast_db( $fasta, $igblast_param_id );

            my $in = Bio::Moose::IgBlastIO->new(
                file   => $igblast_file,
                format => 'format4'
            );

            while ( my $feat = $in->next_feature ) {
                $self->add_object_to_database( $feat, $igblast_param_id,
                    $organism_id );
            }
        }
       
    }


    method create_fasta ( ArrayRef $seq_ids) {
                          # Get files that are ABI and don't have sequences yet
        my $seq = $schema->resultset('Sequence')->search(
            {
                'me.sequence_id' => { '-in' => $seq_ids },
            },
            { join => [ 'putative_annotations', 'organism' ] }
        );

        my $tmp_fasta = File::Temp->new( unlink => 0, DIR => '/tmp/fasta' );
        my $out = Bio::SeqIO->new(
            -file   => '>' . $tmp_fasta->filename,
            -format => 'fasta'
        );

        say "writing fasta";
        while ( my $s = $seq->next ) {

            #say $s->sequence_name;
            my $obj = Bio::Seq->new(
                -id  => $s->id,
                -seq => $s->get_column('sequence')
            );
            $out->write_seq($obj);
        }
        
        return $tmp_fasta->filename;
    }


    method run_igblast_db (Str $file, Int $igblast_param_id ) {

        my $igblast_db = $schema->resultset('IgblastParam')->search(
            { igblast_param_id => $igblast_param_id },
            {
                join => 'organism'
            }
        );

        my $param = $igblast_db->first;
        say $param->igblast_param_v_database;
        say $param->igblast_param_d_database;
        say $param->igblast_param_j_database;
        say $param->igblast_param_auxiliary_data;


        my $r = Bio::Moose::Run::IgBlastN->new(
            query          => $file,
            germline_db_V  => $param->igblast_param_v_database,
            germline_db_D  => $param->igblast_param_d_database,
            germline_db_J  => $param->igblast_param_j_database,
            auxiliary_data => $param->igblast_param_auxiliary_data,
            domain_system  => 'kabat',
            organism       => lc $param->organism->organism_name,
            igdata         => $ENV{IGDATA},
        );

        my $outfile = File::Temp->new( unlink => 0, DIR => '/tmp/igblast' );
        say $outfile->filename;
        open( my $out, '>', $outfile->filename )
          || die "Cannot open/write file " . $outfile->filename . "!";
        say $out $r->out_as_string();
        close($out);

        return ($outfile->filename, $param->organism_id );
    }


    method add_object_to_database ( Object $feat, Int $igblast_param_id, Int $organism_id ) {

        return unless $feat->chain_type;
        my $chain_rs =
          $schema->resultset('ChainType')
          ->find(
            { chain_type_name => { 'like' => $feat->chain_type . '%' } } );

        unless ($chain_rs) {
            $chain_rs =
              $schema->resultset('ChainType')
              ->find( { chain_type_name => { 'like' => 'unknown%' } } );
        }

        die "cannont find " . $feat->chain_type . ' in database'
          unless $chain_rs;

        my $putative_rs = $schema->resultset('PutativeAnnotation');

        my $already_present = $putative_rs->find(
            {
                igblast_param_id => $igblast_param_id,
                sequence_id      => $feat->query_id,
            }
        );

        return if $already_present;

        my $has_mismatches = 0;
        $has_mismatches = 1 if $feat->mismatches;

        my %params = (
            chain_type_id                         => $chain_rs->id,
            igblast_param_id                      => $igblast_param_id,
            putative_annotation_putative_cdr3     => $feat->infer_CDR3_nt,
            putative_annotation_putative_cdr3_aa  => $feat->infer_CDR3_aa,
            sequence_id                           => $feat->query_id,
            organism_id                           => $organism_id,
            putative_annotation_is_reliable       => $feat->is_reliable,
            putative_annotation_is_complete       => $feat->is_complete,
            putative_annotation_is_almost_perfect => $feat->is_almost_perfect,
            putative_annotation_is_perfect        => $feat->is_perfect,
            putative_annotation_has_mismatches    => $has_mismatches,
        );

        # for rearrangement summary
        if ( $feat->rearrangement_summary ) {
            my %r_summary;
            my $summary = $feat->rearrangement_summary;
            my ( $V, $D, $J );
            $V = $summary->top_V_match;
            $D = $summary->top_D_match;
            $J = $summary->top_J_match;

            # leaving only first
            $V =~ s/\,.*//g if $V;
            $D =~ s/\,.*//g if $D;
            $J =~ s/\,.*//g if $J;

            %r_summary = (
                putative_annotation_productive => $summary->productive,
                putative_annotation_stop_codon => $summary->stop_codon,
                putative_annotation_best_v     => $V,
                putative_annotation_best_d     => $D,
                putative_annotation_best_j     => $J,
            );
            @params{ keys %r_summary } = values %r_summary;
        }

        # for alignemnt summary
        if ( $feat->alignments ) {
            my %alns;
            my $aln     = $feat->alignments;
            my @regions = (qw/FWR1 CDR1 FWR2 CDR2 FWR3/);

            foreach my $R (@regions) {
                my $r = lc($R);
                if ( $aln->$R ) {
                    $alns{ "putative_annotation_" . $r . '_mismatches' } =
                      $aln->$R->mismatches;
                    $alns{ "putative_annotation_" . $r . '_gaps' } =
                      $aln->$R->gaps;
                    my ( $mismatches, $insertions, $deletions ) =
                      $feat->infer_aa_diff($R);
                    $alns{ "putative_annotation_" . $r . '_mismatches_aa' } =
                      $mismatches;
                    $alns{ "putative_annotation_" . $r . '_insertions_aa' } =
                      $insertions;
                    $alns{ "putative_annotation_" . $r . '_deletions_aa' } =
                      $deletions;
                }
            }
            @params{ keys %alns } = values %alns;
        }

        # Rendered_alignment
        if ( $feat->alignments ) {
            my %alns;
            my $aln     = $feat->alignments;
            my @regions = (qw/FWR1 CDR1 FWR2 CDR2 FWR3/);

            foreach my $R (@regions) {
                my $r = lc($R);

                if ( $feat->rendered_alignment ) {
                    my $render = $feat->rendered_alignment;
                    if ( $render->query ) {
                        my $q = $render->query;

                        $alns{"putative_annotation_seq_nt"} = $q->sequence;
                        $alns{"putative_annotation_seq_aa"} = $q->translation;

                        my $predicate = 'has_' . $R;

                        if ( $q->sub_regions_sequence ) {
                            my $sub = $q->sub_regions_sequence;
                            if ( $sub->$predicate ) {
                                $alns{ "putative_annotation_" . $r } = $sub->$R;
                            }
                        }
                        if ( $q->sub_regions_translation ) {
                            my $sub = $q->sub_regions_translation;
                            if ( $sub->$predicate ) {
                                $alns{ "putative_annotation_" . $r . "_aa" } =
                                  $sub->$R;
                            }
                        }
                    }
                }
            }
            @params{ keys %alns } = values %alns;
        }


        my $scope = $kiokudb->new_scope;
        my $obj_id = $kiokudb->store($feat);

        $putative_rs->create( { %params, object_id => $obj_id } );

    }


    # Only for heavy_chain
    method run_clustering( Int $assay_id, Int $clustering_type, Int :$igblast_param_id ) {
        # Check if annotated sequences are in database
        $self->check_annotations_in_db($assay_id, $clustering_type, $igblast_param_id ) if $igblast_param_id; 
        my $v_cluster = $self->get_v_cluster_from_db( $assay_id, $clustering_type, igblast_param_id => $igblast_param_id );
        my $clones = $self->get_cdr3_cluster_db( $v_cluster );
        return $clones;
    }

    method get_objects (ArrayRef $ids) {
        
        my $rs = $schema->resultset('PutativeAnnotation')->search(
            {   putative_annotation_id             => { '-IN' => $ids },
                putative_annotation_has_mismatches => 1
            },
            { order_by => [ { "-asc" => 'putative_annotation_putative_cdr3' } ] }
        );
       
        if ( scalar @{$ids} > 2 ) {
            my $scope = $kiokudb->new_scope;

            my @seqs;

            # Creating tree of sequences using clustalw
            while ( my $s = $rs->next ) {
                my $obj = $kiokudb->lookup( $s->object_id );

                # create align object;
                my $aa = join '', @{ $obj->mismatches->{complete_query_aa} };
                my $seqobj = Bio::PrimarySeq->new(
                    -seq => $aa,
                    -id  => $s->putative_annotation_id,
                );

                push @seqs, $seqobj;
            }

            my @params = (
                'ktuple' => 2,
                'matrix' => 'BLOSUM',
                outorder => 'ALIGNED',
                endgaps  => 1
            );
            my $factory = Bio::Tools::Run::Alignment::Clustalw->new(@params);

            #  Pass the factory a list of sequences to be aligned.
            my $aln = $factory->align( \@seqs ); # $aln is a SimpleAlign object.
                                                 # or

            # Or one can pass the factory a pair of (sub)alignments
            #to be aligned against each other, e.g.:
            my $tree = $factory->tree($aln);

            my @nodes = $tree->get_nodes;
            my @ordered_ids;
            foreach my $node (@nodes) {
                if ( $node->is_Leaf ) {
                    my $this_id = $node->id;
                    $this_id =~ s/\/\d+.*$//g;
                    push @ordered_ids, $this_id;
                }
            }

            my @aux = map { "putative_annotation_id = $_ DESC" } @ordered_ids;
            my $orderby = join ',', @aux;

            # return RS with right order
            $rs = $schema->resultset('PutativeAnnotation')->search(
                {
                    putative_annotation_id => { '-IN' => \@ordered_ids },
                    putative_annotation_has_mismatches => 1
                },
                { order_by => $orderby }
            );
        }

        return($rs);
    }
    

__PACKAGE__->meta->make_immutable;
    
1;
