#!/usr/bin/perl

package EhrEntityScraper::PAMF;

use strict;
use warnings;
use vars qw($VERSION @EXPORT @EXPORT_OK %EXPORT_TAGS @ISA);
use Exporter;
use LWP::UserAgent;
use HTML::TreeBuilder;
use HTTP::Response;
use parent qw(EhrEntityScraper);
use HTML::TreeBuilder::XPath;
use URI;

use EhrEntityScraper::Util qw(trim trim_undef parse_visit_type);

sub do_medications {
    my ($self) = @_;

    my $medications = $self->{tree}->findnodes('/html/body//div[@id="medslist"]/div/div[@class="rx"]');
    foreach my $medication (@$medications) {
        my $name             = $medication->look_down('_tag', 'h2')->as_trimmed_text();
        my $instructions     = $medication->look_down('_tag', 'h3')->as_trimmed_text();
        my @div_nodes        = $medication->look_down('_tag', 'div');
        my @p_nodes          = $medication->look_down('_tag', 'p');

        my $prescribing_provider_name;
        my $prescribing_provider_id;
        my $genericname;

        if ($instructions =~ m/^Instructions: (.*)/) {
            $instructions = trim($1);
        }

        foreach my $p_node (@p_nodes) {
            if ($p_node->as_trimmed_text =~ m/^Prescribed by (.*)/) {
                $prescribing_provider_name = trim($1);
            }
        }

        if ($prescribing_provider_name ne "Provider Unknown") {
            $prescribing_provider_id = $self->upsert_provider({fullName  => $prescribing_provider_name,});
        }

        $self->add_medication({
                               medication            => $name,
                               genericname           => $genericname,
                               instructions          => $instructions,
                               prescribingProviderId => $prescribing_provider_id,
                               providerId            => undef,
                               startDate             => '1970-01-01',
                               endDate               => '1970-01-01',
                               status                => undef
                              });
    }
}

sub do_allergies {
    my ($self) = @_;

    my $allergies = $self->{tree}->findnodes('/html/body//table[@id="allergytable"]//tr');
    foreach my $allergy (@$allergies) {
        my @tds = $allergy->look_down('_tag', 'td');
        next if (scalar(@tds) != 2);
        my $allergen = $tds[0]->as_trimmed_text;
        my $reaction = $tds[1]->as_trimmed_text;

        $self->add_allergy({
                           allergen      => $allergen,
                           reaction      => $reaction,
                           severity      => undef,
                           reportedDate  => undef,
                          });
    }
}


1;
