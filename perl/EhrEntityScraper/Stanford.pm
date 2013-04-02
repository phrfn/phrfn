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
use HTML::TreeBuilder::XPath;
use URI;

sub login {
    my $self = shift;

    my $tree = HTML::TreeBuilder::XPath->new_from_content($self->{resp}->decoded_content);
    my $form = $tree->findnodes('/html/body//div[@id="defaultForm"]/form');
    my $post_url = $self->{ehr_entity_url} . $form->[0]->attr('action');
    # break here
    my @inputs = $form->[0]->look_down("_tag", "input");
    my $post_params = $self->make_name_values(\@inputs, {
                                                         Login     => $self->{ehr_entity_user},
                                                         Password  => $self->{ehr_entity_pass},
                                                         jsenabled => 1
                                                       });
    $self->{resp} = $self->ua_post($post_url, $post_params);
}

sub medication_history {
    my $self = shift;
    my $get_url = URI->new_abs("./inside.asp?mode=snapshot", $self->{resp}->base());

    $self->{resp} = $self->ua_get($get_url);

    my $tree = HTML::TreeBuilder::XPath->new_from_content($self->{resp}->decoded_content);
    my $medications = $tree->findnodes('/html/body//div[@id="medslist"]/div/div[@class="rx"]');
    foreach my $medication (@$medications) {
        my $name             = $medication->look_down('_tag', 'h3')->as_trimmed_text();
        my $instructions     = $medication->look_down('_tag', 'span')->as_trimmed_text();
        my @div_nodes        = $medication->look_down('_tag', 'div');
        my @p_nodes          = $medication->look_down('_tag', 'p');

        my $prescribing_provider_name;
        my $prescribing_provider_id;
        my $genericname;

        my $start_date;                                             # XXX
        my $end_date;                                               # XXX
        my $status;                                                 # XXX

        if ($instructions =~ m/^Instructions: (.*)/) {
            $instructions = $self->trim($1);
        }

        foreach my $p_node (@p_nodes) {
            if ($p_node->as_trimmed_text =~ m/^Prescribed by (.*)/) {
                $prescribing_provider_name = $self->trim($1);
            }
        }

        foreach my $div_node (@div_nodes) {
            if ($div_node->as_trimmed_text =~ m/^Generic name: (.*)/) {
                $genericname = $self->trim($1);
            }
        }

        if ($prescribing_provider_name ne "Historical Provider") {
            $prescribing_provider_id = upsert_provider({name => $prescribing_provider_name,});
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

sub upsert_provider {
    my ($self, @provider_data) = @_;
    die "Unimplemented";
}

sub add_medication {
    my ($self, $data) = @_;

    # keep number of attributes in sync with the schema user_medication_history
    die "Invalid medication data.  Not enough number of keys" if (scalar(keys %$data) != 8);

    my $sth = $self->{dbh}->prepare("insert into user_medication_history(" .
                                    "userId, ehrEntityId," .
                                    "medication, genericname, instructions, prescribingProviderId, providerId, startDate, endDate, status" .
                                    ") " .
                                    "values(" .
                                    "?, ?, ?, ?, ?, ?, ?, ?, ?, ?" .
                                    ")");
    $sth->bind_param(1,  $self->{user_id});
    $sth->bind_param(2,  $self->{ehr_entity_id});
    $sth->bind_param(3,  $data->{medication});
    $sth->bind_param(4,  $data->{genericname});
    $sth->bind_param(5,  $data->{instructions});
    $sth->bind_param(6,  $data->{prescribingProviderId});
    $sth->bind_param(7,  $data->{providerId});
    $sth->bind_param(8,  $data->{startDate});
    $sth->bind_param(9,  $data->{endDate});
    $sth->bind_param(10,  $data->{status});

    $sth->execute;
}

1;
