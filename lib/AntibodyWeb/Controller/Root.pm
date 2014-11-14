package AntibodyWeb::Controller::Root;
use Moose;
use namespace::autoclean;
use Data::Printer;

#BEGIN { extends 'Catalyst::Controller' }
# Activating CatalystX::SimpleLogin
BEGIN { extends 'Catalyst::Controller::ActionRole' }


#
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
    my $clones = $c->model('ClusteringAbsDB')->run_clustering($c->req->param('assay'),$c->req->param('clustering'));
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

    my $objects = $c->model('ClusteringAbsDB')->get_objects(\@ids);

    $c->stash( template => 'mutation.tt2', objects => $objects );

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

#sub index :Path :Args(0) {
    #my ( $self, $c ) = @_;

    ## Hello World
    #$c->response->body( $c->welcome_message );
#}

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
