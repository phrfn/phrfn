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

use EhrEntityScraper::Util;

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

sub do_reminders {
    my ($self) = @_;

    my $reminders = $self->{tree}->findnodes('/html/body//table[@id="healthmainttopics"]//tr');
    foreach my $reminder (@$reminders) {
        my @tds = $reminder->look_down('_tag', 'td');
        next if (scalar(@tds) != 4);
        my $reminder_name = trim_undef($tds[0]->as_trimmed_text);
        my $due_date      = trim_undef($tds[1]->as_trimmed_text);
        my $status        = trim_undef($tds[2]->as_trimmed_text);
        my $done_date     = forward_slash_datetime(trim_undef($tds[3]->as_trimmed_text));

        $self->add_health_reminder({
                                    reminderName      => $reminder_name,
                                    dueDateOrTimeFrame      => $due_date,
                                    status      => $status,
                                    doneDate  => $done_date,
                                   });
    }
}

sub do_medical_history {
    my ($self) = @_;

    my $diagnoses = $self->{tree}->findnodes('/html/body//div[@id="medical"]//table//tr');
    foreach my $diagnosis (@$diagnoses) {
        my @tds = $diagnosis->look_down('_tag', 'td');
        next if (scalar(@tds) != 2);
        my $diag  = trim_undef($diagnosis->as_trimmed_text);
        $self->add_medical_history({
                                    historyType              => 'Medical',
                                    relationship             => undef,
                                    diagnosis                => $diag,
                                    diagnosisDateOrTimeFrame => undef,
                                    comments                 => undef,
                                   });
    }

    my $procedures = $self->{tree}->findnodes('/html/body//div[@id="surgical"]/div/table//tr');
    foreach my $procedure (@$procedures) {
        my @tds = $procedure->look_down('_tag', 'td');
        next if (scalar(@tds) != 2);
        my $proc = $tds[0]->as_trimmed_text;
        my $date = trim($tds[1]->as_trimmed_text);
        $date = undef if (length($date) == 0);

        $self->add_medical_history({
                                    historyType              => 'Surgical',
                                    relationship             => undef,
                                    diagnosis                => $proc,
                                    diagnosisDateOrTimeFrame => $date,
                                    comments                 => undef,
                                   });
    }

    my $family_medicals = $self->{tree}->findnodes('/html/body//div[@id="family"]/div/table//tr');
    foreach my $family_medical (@$family_medicals) {
        my @tds = $family_medical->look_down('_tag', 'td');
        next if (scalar(@tds) != 3);
        my $relationship = $tds[0]->as_trimmed_text;
        my $issue        = $tds[1]->as_trimmed_text;
        my $comment      = trim($tds[2]->as_trimmed_text);
        $comment = undef if (length($comment) == 0);

        $self->add_medical_history({
                                    historyType              => 'Family',
                                    relationship             => $relationship,
                                    diagnosis                => $issue,
                                    diagnosisDateOrTimeFrame => undef,
                                    comments                 => $comment,
                                   });
    }
}

sub appointments {
    my $self = shift;
    my $get_url = URI->new_abs("./inside.asp?mode=appointments", $self->{ehr_entity_url});
    # currently no data
}


sub do_components {
    my ($self, $record) = @_;

    my $components = $self->{tree}->findnodes('/html/body//div[@id="results"]//table/tbody/tr');
    $record->{components} = [];
    my $one = {};
    foreach my $component (@$components) {
        my @tds = $component->look_down('_tag', 'td');
        next if (scalar(@tds) != 5 && scalar(@tds) != 1);
        if (scalar(@tds) == 5 && scalar(keys %$one)) {
            push @{$record->{components}}, $one;
            $one = {};
        }
        if (scalar(@tds) == 1) {
            $one->{testComponentResult}  .= $tds[0]->as_trimmed_text;
            next;
        }
        $one->{testComponentName}     = $tds[0]->as_trimmed_text;
        $one->{userValue}             = trim($tds[1]->as_trimmed_text);
        $one->{standardRange}         = trim($tds[2]->as_trimmed_text);
        $one->{units}                 = trim($tds[3]->as_trimmed_text);
        $one->{flag}                  = trim($tds[4]->as_trimmed_text);
    }

    if (scalar(keys %$one)) {
        push @{$record->{components}}, $one;
    } else {
        if (scalar(@{$record->{components}}) == 0) {
            $one->{testComponentResult}   =
            $one->{testComponentName}     =
            $one->{userValue}             =
            $one->{standardRange}         =
            $one->{units}                 =
            $one->{flag}                  = undef;

            push @{$record->{components}}, $one;

        }
    }
}

sub do_narrative {
    my ($self, $record) = @_;
    $record->{imagingNarrative} = undef;
}

sub do_impression {
    my ($self, $record) = @_;
    $record->{imagingImpression} = undef;
}

sub do_general {
    my ($self, $record) = @_;

    $record->{dateSpecimenCollected} = $record->{dateResultProvided} = $record->{providerId} = undef;
    my $general_h3s = $self->{tree}->findnodes('/html/body//div[@id="general"]/div[@class="content"]/h3');
    my $general_ps = $self->{tree}->findnodes('/html/body//div[@id="general"]/div[@class="content"]/p');
    my ($date_specimen_collected, $date_result_provided, $provider_id);
    if (defined($general_h3s) && defined($general_ps) && scalar(@$general_h3s) == scalar(@$general_ps)) {
        for (my $i = 0; $i < scalar(@$general_h3s); ++$i) {
            if ($general_h3s->[$i]->as_trimmed_text =~ m/Collected:/) {
                if ($general_ps->[$i]->as_trimmed_text =~ m/^(\d+\/\d+\/\d+)\s+/) {
                    my @date_comps = split ("/", $1);
                    $record->{dateSpecimenCollected} = sprintf("%d-%0d-%0d", $date_comps[2], $date_comps[0], $date_comps[1]);
                }
            }
            if ($general_h3s->[$i]->as_trimmed_text =~ m/Resulted:/) {
                if ($general_ps->[$i]->as_trimmed_text =~ m/^(\d+\/\d+\/\d+)\s+/) {
                    my @date_comps = split ("/", $1);
                    $record->{dateResultProvided} = sprintf("%d-%0d-%0d", $date_comps[2], $date_comps[0], $date_comps[1]);
                }
            }
            if ($general_h3s->[$i]->as_trimmed_text =~ m/Ordered By:/) {
                if ($general_ps->[$i]->as_trimmed_text =~ m/(.*)/) {
                    my $provider = trim_undef($1);
                    if (defined($provider)) {
                        $record->{providerId} = $self->upsert_provider({fullName => $provider});
                    }
                }
            }
        }
    }
}

sub visits {
    my $self = shift;
    $self->provider_visits();
}

sub provider_visits {
    my $self = shift;
    my $get_url_base = URI->new_abs("./inside.asp?mode=recentappts", $self->{ehr_entity_url});
    my $get_url = $get_url_base;
    my $pg=1;

    while(1) {
        $get_url = $get_url_base . "&pg=$pg" if ($pg ne "1");

        $self->{resp} = $self->ua_get($get_url);
        $self->{tree} = HTML::TreeBuilder::XPath->new_from_content($self->{resp}->decoded_content);

        my $visits = $self->{tree}->findnodes('/html/body//div[@id="appts"]//table//tbody/tr');
        foreach my $visit (@$visits) {
            my @tds = $visit->look_down('_tag', 'td');
            next if (scalar(@tds) != 3);

            my $visit_href = trim_undef($tds[0]->look_down('_tag', 'a')->attr('href'));
            my $visit_obj = {};
            die "no href for visit" if (!defined($visit_href));

            $visit_obj->{description}        = trim_undef($tds[1]->as_trimmed_text);
            $visit_obj->{visitDateTime}      = space_datetime(trim_undef($tds[0]->as_trimmed_text));
            $visit_obj->{departmentOrClinic} = trim_undef($tds[2]->as_trimmed_text);
            $visit_obj->{providerType}       = "outpatient";
            $visit_obj->{dischargeDateTime}  = undef;

            my $visit_id = $self->upsert_user_visit($visit_obj);


            $get_url = URI->new_abs($visit_href, $self->{resp}->base());
            $self->{resp2} = $self->ua_get($get_url);
            $self->{tree2} = HTML::TreeBuilder::XPath->new_from_content($self->{resp2}->decoded_content);
            my $detail1 = $self->{tree2}->findnodes('/html/body//div[@class="report"]/table/tr');
            # die "invalid PAMF visit details page" if (scalar(@$detail1) != 11);

            my ($provider, $reason_for_visit, $visit_type);

            @tds = $detail1->[0]->look_down('_tag', 'td', 'class', 'cdata');
            $provider = trim_undef($tds[2]->as_trimmed_text);
            @tds = $detail1->[1]->look_down('_tag', 'td', 'class', 'cdata');
            $reason_for_visit = trim_undef($tds[0]->as_trimmed_text);
            $visit_type = trim_undef($tds[1]->as_trimmed_text);

            my $visit_details_obj    = {};

            my $visit_vitals_objs    = [];
            my $visit_referrals_objs = [];
            my $visit_tests_objs     = [];
            my $visit_diagnosis_objs = [];

            $visit_details_obj->{userVisitId} = $visit_id;
            $visit_details_obj->{visitTimestamp} = $visit_obj->{visitDateTime};
            $visit_details_obj->{providerId} = $self->upsert_provider({fullName => $provider});
            $visit_details_obj->{reason_for_visit} = $reason_for_visit;
            $visit_details_obj->{visitType}  = $visit_type;

            $visit_details_obj->{vitals} = $visit_details_obj->{diagnosis} = $visit_details_obj->{referrals} =
              $visit_details_obj->{testsOrdered} = $visit_details_obj->{surgery} = 'N';
            for (my $i = 0; $i < scalar(@$detail1); ++$i) {
                next if ($i < 3);
                my @tdh;
                @tdh=$detail1->[$i]->look_down('_tag', 'td', 'class', 'chead');
                @tds=$detail1->[$i]->look_down('_tag', 'td', 'class', 'cdata');
                next if(!scalar(@tdh));
                if (trim($tdh[0]->as_trimmed_text) =~ m/Vitals/) {
                    $visit_vitals_objs = $self->do_visit_vitals(\@tds);
                    $visit_details_obj->{vitals} = 'Y' if (scalar(@$visit_vitals_objs));
                }
                if (trim($tdh[0]->as_trimmed_text) =~ m/Diagnosis/) {
                    $visit_diagnosis_objs = $self->do_visit_diagnosis(\@tds);
                    $visit_details_obj->{diagnosis} = 'Y' if (scalar(@$visit_diagnosis_objs));
                }
                if (trim($tdh[0]->as_trimmed_text) =~ m/Tests and\/or treatments prescribed/) {
                    $visit_referrals_objs = $self->do_visit_referrals(\@tds);
                    $visit_details_obj->{referrals} = 'Y' if (scalar(@$visit_referrals_objs));
                }
                if (trim($tdh[0]->as_trimmed_text) =~ m/Future Orders/) {
                    $visit_tests_objs = $self->do_visit_tests(\@tds, $visit_details_obj->{providerId});
                    $visit_details_obj->{testsOrdered} = 'Y' if (scalar(@$visit_tests_objs));
                }
            }
            my $visit_detail_id = $self->upsert_visit_detail($visit_details_obj);

            $self->add_to_user_visit_vitals($visit_vitals_objs, $visit_detail_id);
            $self->add_to_user_visit_diagnosis($visit_diagnosis_objs, $visit_detail_id);
            $self->add_to_user_visit_referrals($visit_referrals_objs, $visit_detail_id);
            $self->add_to_user_visit_tests($visit_tests_objs, $visit_detail_id);
        }

        my $tfoot_divs = $self->{tree}->findnodes('/html/body//tfoot//div');
        last if (!defined($tfoot_divs) || !scalar(@$tfoot_divs));
        last if (trim($tfoot_divs->[1]->as_trimmed_text) eq "");
        if ($tfoot_divs->[1]->as_trimmed_text ne "Next") {
            print "unexpected tfoot navigation. No active or inactive Next";
            last;
        }
        last if (!defined($tfoot_divs->[1]->look_down('_tag', 'a')));
        $pg++;
    }
}

sub do_visit_vitals {
    my ($self, $tds) = @_;
    my $ret = [];

    while (my $td = shift @$tds) {
        my $tdval = shift @$tds;
        push @$ret, {vitalName => trim_undef($td->as_trimmed_text), vitalValue => trim_undef($tdval->as_trimmed_text)};
    }
    return $ret;
}

sub do_visit_diagnosis {
    my ($self, $tds) = @_;
    my $ret = [];
    foreach my $td (@$tds) {
        push @$ret, {description => trim_undef($td->as_trimmed_text)};
    }
    return $ret;
}

# Provider to which one is referred does not seem to be available right now.
sub do_visit_referrals {
    my ($self, $tds) = @_;
    my $ret = [];
    foreach my $td (@$tds) {
        push @$ret, {
                     providerId => undef,
                     referralInstructions => trim_undef($td->as_trimmed_text),
                    };
    }
    return $ret;
}

sub do_visit_tests {
    my ($self, $tds, $provider_id) = @_;
    my $ret = [];
    while(my $td = shift @$tds) {
        shift @$tds; 
        my $date_ordered = shift @$tds;
        my @date_ordered = split("\/", $date_ordered);
        my $test_id = $self->upsert_test({
                                          testName => trim_undef($td->as_trimmed_text),
                                          dateOrdered => forward_slash_datetime(trim_undef($date_ordered->as_trimmed_text)),
                                          providerId => $provider_id});

        push @$ret, {
                     userTestId => $test_id,
                    };
    }
    return $ret;
}

1;
