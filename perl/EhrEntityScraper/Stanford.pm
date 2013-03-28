#!/usr/bin/perl

package EhrEntityScraper::Stanford;

use strict;
use warnings;
use vars qw($VERSION @EXPORT @EXPORT_OK %EXPORT_TAGS @ISA);
use Exporter;
use LWP::UserAgent;
use HTML::TreeBuilder;
use HTTP::Response;
use parent qw(EhrEntityScraper);

sub login {
    print "stanford login"
}

1;
