package EhrEntityScraper;

use strict;
use warnings;
use DBI;

sub new {
    my $class = shift;
    bless {}, $class;
}

sub initialize {
    my $self = shift;

    $self->{dbh} = DBI->connect ('dbi:mysql:database=phr', 'root', 'root', {RaiseError => 1, AutoCommit => 1});

    $self->{ehr_entity_user} = shift;
    $self->{ehr_entity_pass} = shift;
    $self->{ehr_entity_url} = shift;
}

sub login {
    die "login not overridden";
}

1;
