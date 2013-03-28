#!/usr/bin/perl

package EhrEntityScraper::Scrapers;

use strict;
use warnings;
use vars qw($VERSION @EXPORT @EXPORT_OK %EXPORT_TAGS @ISA);
use Exporter;
use EhrEntityScraper::Stanford;

@ISA    = qw (Exporter);
@EXPORT = qw (getScraper);

my $scrapers = {
                Stanford => 1,
               };

sub getScraper {
    my ($name) = @_;

    if (defined ($scrapers->{$name})) {
        my $qualified_class_name = "EhrEntityScraper::$name";
        return $qualified_class_name->new();
    }
}
