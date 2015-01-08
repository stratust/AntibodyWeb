package AntibodyWeb::Controller::Root;
use Moose;
use namespace::autoclean;
use Data::Printer;
use List::Util qw(max);

#BEGIN { extends 'Catalyst::Controller' }
# Activating CatalystX::SimpleLogin
BEGIN { extends 'Catalyst::Controller::ActionRole' }


# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config(namespace => '');


sub message : Global {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'message.tt2';
    $c->stash->{message}  ||= $c->req->param('message') || 'No message';
}


sub index : Path : Args(0) Does('NeedsLogin') {
    my ( $self, $c ) = @_;
    my @studies = $c->model('AntibodyDB::Study')->all;
    $c->stash(
        template => 'dashboard.tt2',
        studies   => \@studies,
    );
}


sub antibody : Path(/antibody) :Arg(0) Does('NeedsLogin')  {
    my ( $self, $c ) = @_;
    my $cluster = $c->model('ClusteringAbs')->run_clustering;
    $c->stash( $c->model('ClusteringAbs')->output_template($cluster,{}) ); 
    $c->stash( template => 'alignment.tt2');
}


sub clustering : Path(/clustering) :Arg(0) Does('NeedsLogin')  {
    my ( $self, $c ) = @_;
    
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
                ]
        );

    my $igblast_param_id = $c->req->param('analysis_heavy');
    

    my $clones;
    
    if ($igblast_param_id) {

        $clones = $c->model('ClusteringAbsDB')->run_clustering(
            $c->req->param('assay'),
            $c->req->param('clustering'),
            igblast_param_id =>  $igblast_param_id
        );
    }
    else {
        $clones = $c->model('ClusteringAbsDB')->run_clustering(
            $c->req->param('assay'),
            $c->req->param('clustering')
        );
    }
    $c->stash( clones => $clones, colors => \@colors );

    my @clone_ids;
    foreach my $clone (@{$clones}) {
        my @aux;
        foreach my $seq ( @{$clone} ) {
            push @aux, $seq->putative_annotation_id;
        }
        push @clone_ids, join ',', @aux;
    }
    $c->session->{clones} = \@clone_ids;
    
    $c->stash( template => 'alignment.tt2');
}


sub clone :Path('/clone') :Arg(0) Does('NeedsLogin')  {
    my ( $self, $c ) = @_;
    my $arrayref = $c->session->{clones};
    my $seq_ids =  $arrayref->[$c->req->param('clone_id')];
    my @ids = split ",", $seq_ids;
    my $rs = $c->model('AntibodyDB::PutativeAnnotation')->search(
        {
            putative_annotation_id => { '-IN' => \@ids  }
        },
        {
            order_by => [{ "-asc" => 'putative_annotation_putative_cdr3'}]
        }
    );
    $c->stash( template => 'clone.tt2', sequences => $rs );
}


sub mutation :Path('/mutation') :Arg(0) Does('NeedsLogin')  {
    my ( $self, $c ) = @_;
    my $arrayref = $c->session->{clones};
    my $seq_ids =  $arrayref->[$c->req->param('clone_id')];
    my @ids = split ",", $seq_ids;

    my $rs = $c->model('ClusteringAbsDB')->get_objects(\@ids);
    
    $c->stash( template => 'mutation.tt2', rs => $rs  );

}


sub annot_info :Path('/annotinfo') :Arg(1) Does('NeedsLogin')  {
    my ( $self, $c , $putative_annotation_id) = @_;
    my $seq = $c->model('AntibodyDB::PutativeAnnotation')->find({putative_annotation_id => $putative_annotation_id});
    
    $c->stash( template => 'annotation_info.tt2', seq => $seq  );

}


sub create_xls :Path('/getxls') :Arg(0) Does('NeedsLogin')  {
    my ( $self, $c ) = @_;
    my $arrayref = $c->session->{clones};
    my $seq_ids =  $arrayref->[$c->req->param('clone_id')];
    my @ids = split ",", $seq_ids;

    my $rs = $c->model('ClusteringAbsDB')->get_objects(\@ids);

    my @regions = ('FWR1','CDR1','FWR2','CDR2','FWR3');

    my $assay;

    my %size_nuc;
    my %size_aa;

    my %objects;
    while (my $s = $rs->next ){
        $assay = $s->sequence_rel->file->assay->assay_name;
        my $obj = $c->model('KiokuDB')->lookup($s->object_id);
        
        foreach my $region (@regions) {
            push @{$size_nuc{$region}}, scalar @{$obj->mismatches->{germ_regions}->{$region}};
            push @{$size_aa{$region}}, scalar @{$obj->mismatches->{germ_regions_aa}->{$region}};
        }

       $objects{$s->object_id} = $obj;
    }
    
    $rs = $rs->reset;
 
    my %nuc;
    my %aa;

    my %size_region_nuc;
    my %size_region_aa;

    while ( my $s = $rs->next ) {
        my $obj = $objects{ $s->object_id };

        foreach my $region (@regions) {
            my $size_nt = max( @{ $size_nuc{$region} } );
            my $size_aa = max( @{ $size_aa{$region} } );
            $size_region_nuc{$region} = $size_nt;
            $size_region_aa{$region} = $size_aa;

            my $obj_nt_size =
              scalar @{ $obj->mismatches->{germ_regions}->{$region} };
            my $obj_aa_size =
              scalar @{ $obj->mismatches->{germ_regions_aa}->{$region} };

            # for nuc
            if ( $obj_nt_size == $size_nt ) {
                push @{ $nuc{$region} },  $obj->mismatches->{germ_regions}->{$region};
            }
            else {
                my $diff = $size_nt - $obj_nt_size;
                my @aux;

                # add diff in front
                push @aux, ' ' for ( 1 .. $diff );
                push @aux, @{ $obj->mismatches->{germ_regions}->{$region} };
                push @{ $nuc{$region} }, \@aux;
            }

            # for aa
            if ( $obj_nt_size == $size_nt ) {
                push @{ $aa{$region} },
                  $obj->mismatches->{germ_regions_aa}->{$region};
            }
            else {
                my $diff = $size_aa - $obj_aa_size;
                my @aux;

                # add diff in front
                push @aux, '' for ( 1 .. $diff );
                push @aux, @{ $obj->mismatches->{germ_regions_aa}->{$region} };
                push @{ $aa{$region} }, \@aux;
            }
        }
    }

    
    $rs = $rs->reset;
    $c->stash(
        rs              => $rs,
        objects         => \%objects,
        nuc             => \%nuc,
        aa              => \%aa,
        regions         => \@regions,
        size_region_nuc => \%size_region_nuc,
        size_region_aa  => \%size_region_aa,
        worksheet_name  => 'test',
        template        => 'excel.tt2',
        USE_UNICODE     => 1,
    );

    my $filename = $assay;
    $filename =~ s/\s+/\_/g;
    $filename .= "_clone_" . ( $c->req->param('clone_id') + 1 ) . '.xlsx';

    if ( $c->forward( $c->view('Excel') ) ) {
#     $c->forward( $c->view('Excel') ); 
        $c->response->content_type('application/x-msexcel');
        $c->response->header( 'Content-Disposition',
            "attachment; filename=$filename" );
    }

}


=encoding utf-8

=head1 NAME

AntibodyWeb::Controller::Root - Root Controller for AntibodyWeb

=head1 DESCRIPTION

[enter your description here]

=head1 METHODS

=head2 index

The root page (/)

=cut


=head2 default

Standard 404 error page

=cut

sub default :Path {
    my ( $self, $c ) = @_;
    $c->response->body( 'Page not found' );
    $c->response->status(404);
}

=head2 end

Attempt to render a view, if needed.

=cut

sub end : ActionClass('RenderView') {
    #my ( $self, $c ) = @_;
    #$c->log->debug("\$var is: ". p($c->stash));
}

=head1 AUTHOR

Catalyst developer

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
