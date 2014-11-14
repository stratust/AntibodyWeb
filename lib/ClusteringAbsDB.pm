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

    method get_v_cluster_from_db ( Int $assay_id, Int $clustering_type) {
        my %v_cluster;
        my $sequence_rs;
        my $scope = $kiokudb->new_scope;

        if ( $clustering_type == 1 ) {
            $sequence_rs = $schema->resultset('PutativeAnnotation')->search( 
                { 
                    assay_id => $assay_id,
                    chain_type_name => { "like" => '%heavy%' },
                    putative_annotation_putative_cdr3 => { "!=" => 'N/A' },
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

#            my $i = 1;
            #while ( my $s = $sequence_rs->next ) {
                #my $heavy_seq = $s->sequence_rel;

                ##say $heavy_seq->get_column('sequence_name');
                #my $heavy_has_light = $heavy_seq->sequence_has_sequence_heavy_files->first;
                #my $light_seq       = $heavy_has_light->light_file;

                ##say join " => ",($heavy_seq->get_column('sequence_name'),$light_seq->get_column('sequence_name'));
                #my $heavy_putative = $heavy_seq->putative_annotations->first;
                #my $light_putative = $light_seq->putative_annotations->first;
                #$combo{$i}{H} = $kiokudb->lookup( $heavy_putative->object_id );
                #$combo{$i}{L}{kappa} = $kiokudb->lookup( $light_putative->object_id );
                #$i++;
            #}

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


    # Only for heavy_chain
    method run_clustering( Int $assay_id, Int $clustering_type ) {
        my $combo;
        my $v_cluster = $self->get_v_cluster_from_db( $assay_id, $clustering_type );
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
        
        my $scope = $kiokudb->new_scope;
        
        my @seqs;
        while ( my $s = $rs->next ) {
            my $obj = $kiokudb->lookup( $s->object_id );
            push @seqs, $obj;
        }

        return(\@seqs);
    }


__PACKAGE__->meta->make_immutable;
    
1;
