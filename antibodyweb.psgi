use strict;
use warnings;

use AntibodyWeb;

my $app = AntibodyWeb->apply_default_middlewares(AntibodyWeb->psgi_app);
$app;

