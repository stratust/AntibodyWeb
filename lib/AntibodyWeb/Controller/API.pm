package AntibodyWeb::Controller::API;

use strict;
use warnings;
use Moose;
use namespace::autoclean;
use utf8;
use Data::Printer;
BEGIN {extends 'Catalyst::Controller::REST'}

__PACKAGE__->config( default => 'application/json; charset=UTF-8' );

sub error : ActionClass('REST') {
 
}

sub error_POST {
	my ( $self, $c ) = @_;
	$self->status_bad_request( $c, message => "Problem, you are not logged!", );
}


sub get_JSON_from_table {
    my ($self, $c, $rs, $additional_keys ) = @_;
    my @json;
    while ( my $row = $rs->next ) {
        my %aux;
        foreach my $col ( $rs->result_source->columns ) {
            $aux{$col} = $row->get_column($col);
        }
        # map aditional keys 
        foreach my $key (sort {$a cmp $b } keys %{$additional_keys}) {
            my $this_col = $additional_keys->{$key};
            if ($row->get_column($this_col)){
                $aux{$key} = $row->get_column($this_col);
            }
            else{
                $c->log->debug( "Cannot find this column: $this_col in table");
            }
        }
        push @json,\%aux;
    }
    return \@json;
}


sub assaylist : Path('/api/assaylist')  Args(0) : ActionClass('REST') Does('NeedsLogin') {
}

sub assaylist_GET {
    my ( $self, $c ) = @_;
    my $study_id = $c->request->param('study_id');
    my $table="Assay";
    my $rs = $c->model('AntibodyDB::'.$table)->search({study_id => $study_id});
    # Map new keys to hash (when used by jquery component)
    my %new_keys = ( label => 'assay_name', value => 'assay_id' );
    my $json = $self->get_JSON_from_table($c, $rs, \%new_keys);

    $self->status_ok( $c, entity => $json );
}


sub igblastlist : Path('/api/igblastlist')  Args(0) : ActionClass('REST') Does('NeedsLogin') {
}

sub igblastlist_GET {
	my ( $self,$c) = @_;
    my $table="IgblastParam";
    my $rs = $c->model('AntibodyDB::'.$table);
    # Map new keys to hash (when used by jquery component)
    my %new_keys = ( label => 'igblast_param_name', value => 'igblast_param_id' );
    my $json = $self->get_JSON_from_table($c, $rs, \%new_keys);
    $self->status_ok( $c, entity => $json );
}


sub sequence_list_heavy : Path('/api/get_heavy_sequence')  Args(0) : ActionClass('REST') Does('NeedsLogin') {
}

sub sequence_list_heavy_GET {
	my ( $self,$c) = @_;
    
    my $offset = $c->req->param('start');
    my $rows = $c->req->param('length');
    $offset = 0 unless $offset;
    $rows = 10 unless $rows;

    my $table="PutativeAnnotation";

    my $ord_col =  $c->req->param('order[0][column]');
    $c->log->debug('my order_col:'.$ord_col);
    
    my $ord_col_name = $c->req->param('columns['.$ord_col.'][data]');
    $c->log->debug('my order_col_name:'.$ord_col_name);
    $ord_col_name = "me.$ord_col_name" if ($ord_col_name && $ord_col_name =~ /sequence_id/);

    my $ord_direction = $c->req->param('order[0][dir]');
    $c->log->debug('my order_col_direction:'.$ord_direction);

    my $order;
    $order = { "-$ord_direction" => $ord_col_name } if ( $ord_col_name && $ord_direction );
    
    $order = { -asc => 'me.sequence_id'} unless $order;

    
    my $rs = $c->model( 'AntibodyDB::' . $table  );
    my $heavy_chain = $c->model('AntibodyDB::ChainType')->search( { chain_type_name => { "like" => '%heavy%' } } )->first;
    my $total = $rs->count;
    $rs = $rs->search( 
       { 
            '-or'=> [ 
                sequence_name => { like => "%" . uc( $c->req->param('search[value]') ) . "%" },
                putative_annotation_best_v => { like => "%" . uc( $c->req->param('search[value]') ) . "%" },
                putative_annotation_best_d => { like => "%" . uc( $c->req->param('search[value]') ) . "%" },
                putative_annotation_best_j => { like => "%" . uc( $c->req->param('search[value]') ) . "%" },
            ],
            chain_type_id => $heavy_chain->id
        },

        {
            join => 'sequence_rel',
            '+select' => [ qw/ sequence_rel.sequence_name / ],
            '+as' => [qw/sequence_name/],
        }
    );

    my $total_after_filter = $rs->count;

    #pagination
    $rs = $rs->search( 
        {}, 
        { 
            offset => $offset,
            rows => $rows,
            order_by => $order,
 
        } 
    );
    # Map new keys to hash (when used by jquery component)
    my %aux = ( recordsTotal => $total, recordsFiltered => $total_after_filter );
    my $json = $self->get_JSON_from_table($c, $rs, { sequence_name => 'sequence_name' } );
    $self->status_ok( $c, entity => {
           data => $json, 
           %aux,
        }
    );
}


sub sequence_list_light : Path('/api/get_light_sequence')  Args(0) : ActionClass('REST') Does('NeedsLogin') {
}

sub sequence_list_light_GET {
	my ( $self,$c) = @_;
    
    my $offset = $c->req->param('start');
    my $rows = $c->req->param('length');
    $offset = 0 unless $offset;
    $rows = 10 unless $rows;

    my $table="PutativeAnnotation";

    my $ord_col =  $c->req->param('order[0][column]');
    $c->log->debug('my order_col:'.$ord_col);
    
    my $ord_col_name = $c->req->param('columns['.$ord_col.'][data]');
    $c->log->debug('my order_col_name:'.$ord_col_name);
    $ord_col_name = "me.$ord_col_name" if ($ord_col_name && $ord_col_name =~ /sequence_id/);

    my $ord_direction = $c->req->param('order[0][dir]');
    $c->log->debug('my order_col_direction:'.$ord_direction);

    my $order;
    $order = { "-$ord_direction" => $ord_col_name } if ( $ord_col_name && $ord_direction );
    
    $order = { -asc => 'me.sequence_id'} unless $order;

    
    my $rs = $c->model( 'AntibodyDB::' . $table  );

    my $heavy_chain = $c->model('AntibodyDB::ChainType')->search(
        {   -or => [
                chain_type_name => { "like" => '%lambda%' },
                chain_type_name => { "like" => '%kappa%' },
            ]
        }
    )->first;

    my $total = $rs->count;
    $rs = $rs->search( 
        { 
            '-or'=> [ 
                sequence_name => { like => "%" . uc( $c->req->param('search[value]') ) . "%" },
                putative_annotation_best_v => { like => "%" . uc( $c->req->param('search[value]') ) . "%" },
                putative_annotation_best_j => { like => "%" . uc( $c->req->param('search[value]') ) . "%" },
            ],
            chain_type_id => $heavy_chain->id
        },
        {
            join => 'sequence_rel',
            '+select' => [ qw/ sequence_rel.sequence_name / ],
            '+as' => [qw/sequence_name/],
        }
    );

    my $total_after_filter = $rs->count;

    #pagination
    $rs = $rs->search( 
        {}, 
        { 
            offset => $offset,
            rows => $rows,
            order_by => $order,
        } 
    );
    # Map new keys to hash (when used by jquery component)
    my %aux = ( recordsTotal => $total, recordsFiltered => $total_after_filter );
    my $json = $self->get_JSON_from_table($c, $rs, { sequence_name => 'sequence_name' } );
    $self->status_ok( $c, entity => {
           data => $json, 
           %aux,
        }
    );
}


1;
