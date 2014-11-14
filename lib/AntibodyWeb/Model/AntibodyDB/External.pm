package AntibodyWeb::Model::AntibodyDB::External;
    use Moose;
    use Method::Signatures;
    use Config::JFDI;
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use AntibodyDB::Schema;
    use Sys::Hostname;
    use KiokuDB;
    use namespace::autoclean;

    has 'config' => (
        is            => 'ro',
        isa           => 'HashRef',
        lazy          => 1,
        builder       => '_build_config',
        documentation => 'Get DB configuration',
    );

    has 'schema' => (
        is            => 'ro',
        isa           => 'DBIx::Class::Schema',
        lazy          => 1,
        builder       => '_build_schema',
        documentation => 'Dbix::Class::Schema Object',
    );

    has 'kiokudb' => (
        is            => 'ro',
        isa           => 'KiokuDB',
        lazy          => 1,
        builder       => '_build_kiokudb',
        documentation => 'Dbix::Class::Schema Object',
    );

    method _build_config () {
        my ($host) = Sys::Hostname::hostname() =~ m/^([^\.]+)/;
        my $path;
        if ( -e "$FindBin::Bin/../conf/antibodyweb_" . $host . '.conf' ) {
            $path = "$FindBin::Bin/../conf/antibodyweb_" . $host . '.conf';
        }
        elsif ( -e "$FindBin::Bin/../../AntibodyWeb/conf/antibodyweb_" . $host . '.conf' ) {
            $path = "$FindBin::Bin/../../AntibodyWeb/conf/antibodyweb_" . $host . '.conf';
        }
        elsif ( -e "$FindBin::Bin/conf/antibodyweb_" . $host . '.conf' ) {
            $path = "$FindBin::Bin/conf/antibodyweb_" . $host . '.conf';
        }
        else {
            die "No configuration file found!!!";
        }
        my $config = Config::JFDI->new(
            name => 'AntibodyWeb',
            path => $path,
        )->get;
        return $config;
    }

    method _build_schema () {
        my $schema = AntibodyDB::Schema->connect(
            @{ $self->config->{'Model::AntibodyDB'}{connect_info} || [] } );
        return $schema;
    }

    method _build_kiokudb () {
        my @aux = @{ $self->config->{'Model::AntibodyDB'}{connect_info} || [] };
        my $dir = KiokuDB->connect( $aux[0], user => $aux[1], password => $aux[2] );
        return $dir;
    }

 __PACKAGE__->meta->make_immutable;    

1;
