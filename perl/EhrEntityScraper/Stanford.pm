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

use EhrEntityScraper::Util;

sub appointments {
    # There's currently no apptmts in the Evan's stanford a/c
}

sub visits {
    my $self = shift;
    $self->hospital_visits();                                        # Stanford has separate hospital visits
    $self->provider_visits();
}

sub hospital_visits {
    my $self = shift;
    my $get_url_base = "https://myhealth.stanfordmedicine.org/myhealth/inside.asp?mode=admissions";
    my $get_url = $get_url_base;
    my $pg=1;

    while(1) {
        $get_url = $get_url_base . "&pg=$pg" if ($pg ne "1");

        $self->{resp} = $self->ua_get($get_url);
        $self->{tree} = HTML::TreeBuilder::XPath->new_from_content($self->{resp}->decoded_content);

        my $admissions = $self->{tree}->findnodes('/html/body//div[@id="hospitalizations"]//table//tbody/tr');
        foreach my $admission (@$admissions) {
            my @tds = $admission->look_down('_tag', 'td');
            next if (scalar(@tds) != 3);

            my $visit_obj = {};

            $visit_obj->{description}        = undef;
            $visit_obj->{visitDateTime}      = forward_slash_datetime(trim_undef($tds[0]->as_trimmed_text));
            $visit_obj->{departmentOrClinic} = trim_undef($tds[2]->as_trimmed_text);
            $visit_obj->{providerType}       = "inpatient";
            $visit_obj->{dischargeDateTime}  = forward_slash_datetime(trim_undef($tds[0]->as_trimmed_text));

            my $visit_id = $self->upsert_user_visit($visit_obj);
        }

        my $tfoot_divs = $self->{tree}->findnodes('/html/body//tfoot//div');
        last if (!defined($tfoot_divs) || !scalar(@$tfoot_divs));
        if ($tfoot_divs->[1]->as_trimmed_text ne "Next") {
            print "unexpected tfoot navigation. No active or inactive Next";
            last;
        }
        last if (!defined($tfoot_divs->[1]->look_down('_tag', 'a')));
        $pg++;
    }
}

sub provider_visits {
    my $self = shift;
    my $get_url_base = "https://myhealth.stanfordmedicine.org/myhealth/inside.asp?mode=recentappts";
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
            my $detail1 = $self->{tree2}->findnodes('/html/body//div[@class="report"]/table[@class="rz_1"]/tr/td/table/tr/td');
            die "invalid visit details page" if (scalar(@$detail1) != 8);

            my ($provider, $reason_for_visit);
            if (trim_undef($detail1->[6]->as_trimmed_text) =~ m/Provider:\s*(.*)/) {
                $provider = $1;
            }
            if (trim_undef($detail1->[7]->as_trimmed_text) =~ m/Department:\s*(.*)/) {
                $reason_for_visit = $1;
            }
            my $visit_details_obj        = {};
            my $visit_surgeries_objs      = [];
            my $visit_tests_objs = [];
            my $visit_diagnosis_objs = [];

            $visit_details_obj->{userVisitId} = $visit_id;
            $visit_details_obj->{visitTimestamp} = $visit_obj->{visitDateTime};
            $visit_details_obj->{providerId} = $self->upsert_provider({fullName => $provider});
            $visit_details_obj->{reason_for_visit} = $reason_for_visit;
            $visit_details_obj->{visitType}  = parse_visit_type(trim_undef($detail1->[1]->as_trimmed_text));

            $visit_details_obj->{diagnosis} = $visit_details_obj->{vitals} = $visit_details_obj->{referrals} =
              $visit_details_obj->{testsOrdered} = $visit_details_obj->{surgery} = 'N';

            my $detail2 = $self->{tree2}->findnodes('/html/body//div[@class="report"]/table[@class="rz_4" or @class="rz_k"]');
            while (my $table = shift @$detail2) {
                my $val_table;
                if (trim($table->as_trimmed_text) =~ m/You Were Diagnosed With/) {
                    $table = shift @$detail2;
                    my @trs = $table->look_down('_tag', 'tr');
                    foreach my $tr (@trs) {
                        my $visit_diagnosis_obj = {};
                        my @tds = $tr->look_down('_tag', 'td');
                        if (!scalar(@tds) || scalar(@tds) != 4) { print "invalid number of columns in lab and imaging orders"; next;}

                        $visit_diagnosis_obj->{description} = trim_undef($tds[1]->as_trimmed_text);
                        push @$visit_diagnosis_objs, $visit_diagnosis_obj;
                    }

                    $visit_details_obj->{diagnosis} = 'Y';
                }
                if (trim($table->as_trimmed_text) =~ m/Lab and Imaging Orders/) {
                    $table = shift @$detail2;
                    my @trs = $table->look_down('_tag', 'tr');                     shift @trs;

                    foreach my $tr (@trs) {
                        my $visit_tests_obj;
                        my @tds = $tr->look_down('_tag', 'td');
                        if (!scalar(@tds) || scalar(@tds) != 3) { print "invalid number of columns in lab and imaging orders"; next;}

                        $visit_tests_obj->{userTestId} = $self->upsert_test({testName => trim_undef($tds[1]->as_trimmed_text),
                                                                             dateOrdered => forward_slash_datetime(trim_undef($tds[2]->as_trimmed_text)),
                                                                             providerId => $visit_details_obj->{providerId}});
                        push @$visit_tests_objs, $visit_tests_obj;
                    }

                    $visit_details_obj->{testsOrdered} = 'Y';
                }
                if (trim($table->as_trimmed_text) =~ m/Surgery Information/) {
                    $table = shift @$detail2;
                    my @trs = $table->look_down('_tag', 'tr');
                    shift @trs;

                    foreach my $tr (@trs) {
                        my $visit_surgeries_obj = {};
                        my @tds = $tr->look_down('_tag', 'td');
                        if (!scalar(@tds) || scalar(@tds) != 9) { print "invalid number of columns in surgery informaion"; next;}

                        $visit_surgeries_obj->{primaryProcedure}  = trim_undef($tds[5]->as_trimmed_text);
                        $visit_surgeries_obj->{dateTimePerformed} = forward_slash_datetime(trim_undef($tds[2]->as_trimmed_text));
                        $visit_surgeries_obj->{providerId}        = $self->upsert_provider({fullName => trim_undef($tds[4]->as_trimmed_text)});
                        $visit_surgeries_obj->{location}          = trim_undef($tds[6]->as_trimmed_text);
                        $visit_surgeries_obj->{status}            = trim_undef($tds[3]->as_trimmed_text);

                        push @$visit_surgeries_objs, $visit_surgeries_obj;
                    }

                    $visit_details_obj->{surgery} = 'Y';
                }
            }
            my $visit_detail_id = $self->upsert_visit_detail($visit_details_obj);

            $self->add_to_user_visit_diagnosis($visit_diagnosis_objs, $visit_detail_id);
            $self->add_to_user_visit_tests($visit_tests_objs, $visit_detail_id);
            $self->add_to_user_visit_surgeries($visit_surgeries_objs, $visit_detail_id);
        }

        my $tfoot_divs = $self->{tree}->findnodes('/html/body//tfoot//div');
        last if (!defined($tfoot_divs) || !scalar(@$tfoot_divs));
        if ($tfoot_divs->[1]->as_trimmed_text ne "Next") {
            print "unexpected tfoot navigation. No active or inactive Next";
            last;
        }
        last if (!defined($tfoot_divs->[1]->look_down('_tag', 'a')));
        $pg++;
    }
}

sub do_components {
    my ($self, $record) = @_;

    $record->{components} = [];
    my $one = {};

    $one->{testComponentName}   = undef;
    $one->{userValue}           = undef;
    $one->{standardRange}       = undef;
    $one->{units}               = undef;
    $one->{flag}                = undef;
    $one->{testComponentResult} = undef;

    push @{$record->{components}}, $one;

    # Stanford has no components, log a message if we see something here in the future..
    my $div = $self->{tree}->findnodes('/html/body//div[@id="results"]');
    if (defined($div) && scalar(@$div)) {
        if ($div->[0]->as_trimmed_text !~ m/There is no component information for this result/) {
            print "got non-image test for Stanford";
        }
    }
}

sub do_narrative {
    my ($self, $record) = @_;

    $record->{imagingNarrative} = undef;
    my $div = $self->{tree}->findnodes('/html/body//div[@id="narrative"]');
    if (defined($div) && scalar(@$div)) {
        if ($div->[0]->as_trimmed_text =~ m/(Narrative)?(.*)/) {
            $record->{imagingNarrative} = $2;
        } else {
            print "something wrong, image narrative has no valid text";
        }
    }
}

sub do_impression {
    my ($self, $record) = @_;

    $record->{imagingImpression} = undef;
    my $div = $self->{tree}->findnodes('/html/body//div[@id="impression"]');
    if (defined($div) && scalar(@$div)) {
        if ($div->[0]->as_trimmed_text =~ m/(Impression)?(IMPRESSION:)?(.*)/) {
            $record->{imagingImpression} = $3;
        } else {
            print "something wrong, image impression has no valid text";
        }
    }
}


sub do_general {
    my ($self, $record) = @_;

    $record->{dateSpecimenCollected} = $record->{dateResultProvided} = $record->{providerId} = undef;
    my $general_spans = $self->{tree}->findnodes('/html/body//div[@id="general"]/div[@class="content"]/span');
    my $general_ps = $self->{tree}->findnodes('/html/body//div[@id="general"]/div[@class="content"]/p');
    my ($date_specimen_collected, $date_result_provided, $provider_id);
    if (defined($general_spans) && defined($general_ps) && scalar(@$general_spans) == scalar(@$general_ps)) {
        for (my $i = 0; $i < scalar(@$general_spans); ++$i) {
            if ($general_spans->[$i]->as_trimmed_text =~ m/Collected:/) {
                if ($general_ps->[$i]->as_trimmed_text =~ m/^(\d+\/\d+\/\d+)\s+/) {
                    my @date_comps = split ("/", $1);
                    $record->{dateSpecimenCollected} = sprintf("%d-%0d-%0d", $date_comps[2], $date_comps[0], $date_comps[1]);
                }
            }
            if ($general_spans->[$i]->as_trimmed_text =~ m/Resulted:/) {
                if ($general_ps->[$i]->as_trimmed_text =~ m/^(\d+\/\d+\/\d+)\s+/) {
                    my @date_comps = split ("/", $1);
                    $record->{dateResultProvided} = sprintf("%d-%0d-%0d", $date_comps[2], $date_comps[0], $date_comps[1]);
                }
            }
            if ($general_spans->[$i]->as_trimmed_text =~ m/Ordered By:/) {
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

sub do_medications {
    my ($self) = @_;

    my $medications = $self->{tree}->findnodes('/html/body//div[@id="medslist"]/div/div[@class="rx"]');
    foreach my $medication (@$medications) {
        my $name             = $medication->look_down('_tag', 'h3')->as_trimmed_text();
        my $instructions     = $medication->look_down('_tag', 'span')->as_trimmed_text();
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

        foreach my $div_node (@div_nodes) {
            if ($div_node->as_trimmed_text =~ m/^Generic name: (.*)/) {
                $genericname = trim($1);
            }
        }

        if ($prescribing_provider_name ne "Historical Provider") {
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

    my $allergies = $self->{tree}->findnodes('/html/body//div[@id="allergy"]/div/table//tr');
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

sub do_medical_history {
    my ($self) = @_;

    my $diagnoses = $self->{tree}->findnodes('/html/body//div[@id="medical"]/div/table//tr');
    foreach my $diagnosis (@$diagnoses) {
        my @tds = $diagnosis->look_down('_tag', 'td');
        next if (scalar(@tds) != 2);
        my $diag  = $tds[0]->as_trimmed_text;
        my $date  = trim($tds[1]->as_trimmed_text);
        $date = undef if (length($date) == 0);

        $self->add_medical_history({
                                    historyType              => 'Medical',
                                    relationship             => undef,
                                    diagnosis                => $diag,
                                    diagnosisDateOrTimeFrame => $date,
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

1;
