package AntibodyWeb;
use Moose;
use namespace::autoclean;

use Catalyst::Runtime 5.80;

# Set flags and add plugins for the application.
#
# Note that ORDERING IS IMPORTANT here as plugins are initialized in order,
# therefore you almost certainly want to keep ConfigLoader at the head of the
# list if you're using it.
#
#         -Debug: activates the debug mode for very useful log messages
#   ConfigLoader: will load the configuration from a Config::General file in the
#                 application's home directory
# Static::Simple: will serve static files from the application's root
#                 directory

use Catalyst qw/
    -Debug
    Static::Simple
    ConfigLoader::Multi
    +CatalystX::SimpleLogin
    Authentication
    Authorization::Roles
    Session
    Session::State::Cookie
    Session::Store::FastMmap
    Compress
    RunAfterRequest
    AutoCRUD
    /;

extends 'Catalyst';
use Sys::Hostname;

our $VERSION = '0.01';

# Configure the application.
#
# Note that settings in antibodyweb.conf (or other external
# configuration file that you set up manually) take precedence
# over this when using ConfigLoader. Thus configuration
# details given here can function as a default configuration,
# with an external configuration file acting as an override for
# local deployment.

# Retriving hostname
my ($host) = Sys::Hostname::hostname() =~ m/^([^\.]+)/;

__PACKAGE__->config(
    name => 'AntibodyWeb',
    # Disable deprecated behavior needed by old applications
    disable_component_resolution_regex_fallback => 1,
    enable_catalyst_header                      => 1,        # Send X-Catalyst header
    using_frontend_proxy                        => 1,        # If there is a frontend_proxy
    default_view                                => 'HTML',
    'View::HTML'                                => {
        INCLUDE_PATH => [
            __PACKAGE__->path_to( 'root' ),
            __PACKAGE__->path_to( 'root', 'src' ),
            __PACKAGE__->path_to( 'root', 'lib' ),
            __PACKAGE__->path_to( 'root', 'login' ),
       ],
        PRE_PROCESS => 'config/main',
        WRAPPER     => 'site2/wrapper',
        ERROR       => 'error.tt2',
        TIMER       => 0,
        render_die  => 1,
        TEMPLATE_EXTENSION => '.tt2',
    },
    'Plugin::Static::Simple' =>
      { include_path => [ __PACKAGE__->path_to( 'root', 'static' ), ], },
 
     'Plugin::ConfigLoader' => {
        file                => __PACKAGE__->path_to('conf'),
        config_local_suffix => 'antibodyweb_' . $host,
    },
    'Plugin::Authentication' => {
        default => {
            credential => {
                class          => 'Password',
                password_field => 'password',
                password_type  => 'clear'
            },
            store => {
                class => 'Minimal',
                users => { 'stratus' => { password => '1234' }, },
            },
        },
    },
    'Plugin::Session' => {
        flash_to_stash => 1
    },
    'Controller::Login' => {
        traits => [
            'WithRedirect',           # Optional, enables redirect-back feature
            '-RenderAsTTTemplate',    # Optional, allows you to use your own template
        ],
        },

);

# Start the application
__PACKAGE__->setup();

=encoding utf8

=head1 NAME

AntibodyWeb - Catalyst based application

=head1 SYNOPSIS

    script/antibodyweb_server.pl

=head1 DESCRIPTION

[enter your description here]

=head1 SEE ALSO

L<AntibodyWeb::Controller::Root>, L<Catalyst>

=head1 AUTHOR

Catalyst developer

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
