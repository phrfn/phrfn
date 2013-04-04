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

use EhrEntityScraper::Util qw(trim trim_undef parse_visit_type);

sub login {
    my $self = shift;

    $self->{tree} = HTML::TreeBuilder::XPath->new_from_content($self->{login_page}->decoded_content);
    my $form = $self->{tree}->findnodes('/html/body//div[@id="defaultForm"]/form');
    my $post_url = $self->{ehr_entity_url} . $form->[0]->attr('action');
    my @inputs = $form->[0]->look_down("_tag", "input");
    my $post_params = $self->make_name_values(\@inputs, {
                                                         Login     => $self->{ehr_entity_user},
                                                         Password  => $self->{ehr_entity_pass},
                                                         jsenabled => 1,
                                                         'submit' => 'Sign In',
                                                       });
    # always perform real login regardless of canned config
    my $saved_canned_config = $self->canned_config();
    $self->set_canned_config({save_to_canned => 0, read_from_canned => 0});
    $self->{resp} = $self->ua_post($post_url, $post_params);
    $self->set_canned_config($saved_canned_config);
}

sub health_summary {
    my $self = shift;
    my $get_url = URI->new_abs("./inside.asp?mode=snapshot", $self->{resp}->base());

    $self->{resp} = $self->ua_get($get_url);
    $self->{tree} = HTML::TreeBuilder::XPath->new_from_content($self->{resp}->decoded_content);

    $self->do_medications();
    $self->do_allergies();
    $self->do_immunizations();
}

sub medical_history {
    my $self = shift;
    my $get_url = URI->new_abs("./inside.asp?mode=histories", $self->{resp}->base());

    $self->{resp} = $self->ua_get($get_url);
    $self->{tree} = HTML::TreeBuilder::XPath->new_from_content($self->{resp}->decoded_content);

    $self->do_medical_history();
}

sub appointments {
}

sub tests {
    my $self = shift;
    my $get_url = URI->new_abs("./inside.asp?mode=labs", $self->{resp}->base());
    my $pg=1;

    while (1) {
        $get_url = $get_url . "&pg=$pg" if ($pg ne "1");

        $self->{resp} = $self->ua_get($get_url);
        $self->{tree} = HTML::TreeBuilder::XPath->new_from_content($self->{resp}->decoded_content);

        my $tests = $self->{tree}->findnodes('/html/body//div[@id="labs"]//table//tbody/tr');
        foreach my $test (@$tests) {
            my @tds = $test->look_down('_tag', 'td');
            next if (scalar(@tds) != 3);
            my $date  = trim_undef($tds[0]->as_trimmed_text);
            my @date = split("/", $date);
            my $test_name  = trim_undef($tds[1]->as_trimmed_text);
            my $test_href = $tds[1]->look_down('_tag', 'a')->attr('href');
            my $provider  = trim_undef($tds[2]->as_trimmed_text);
            my $provider_id = $self->upsert_provider({fullName => $provider});
            my $test_obj = {
                            testName                 => $test_name,
                            dateOrdered              => sprintf("%d-%0d-%0d", $date[2], $date[0], $date[1]),
                            providerId               => $provider_id,
                           };

            my $test_id = $self->add_tests($test_obj);
            $self->test_components($test_id, $test_obj, $test_href);
        }
        my $tfoot_divs = $self->{tree}->findnodes('/html/body//tfoot/div');
        last if (!defined($tfoot_divs) || !scalar(@$tfoot_divs));
        if ($tfoot_divs->[1]->as_trimmed_text ne "Next") {
            print "unexpected tfoot navigation. No active or inactive Next";
            last;
        }
        last if (!defined($tfoot_divs->[1]->look_down('_tag', 'a')));
        $pg++;
    }
}

sub visits {
    my $self = shift;
    $self->hospital_visits();                                        # Stanford has separate hospital visits
    # $self->provider_visits();
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

            my $visit_id = $self->add_to_user_visits($visit_obj);
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

            my $visit_id = $self->add_to_user_visits($visit_obj);


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
            my $visit_detail_id = $self->add_to_user_visit_details($visit_details_obj);

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

    $record->{testComponentName} = $record->{userValue} = $record->{standardRange} = $record->{units} = 
      $record->{flag} = $record->{testComponentResult} = undef;

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
                    $record->{dateSpecimenCollected} = sprintf("%d-%0d-%0d", $date_comps[2], $date_comps[0], $date_comps[1]);
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

sub test_components {
    my ($self, $test_id, $test, $href) = @_;

    my $get_url = URI->new_abs($href, $self->{resp}->base());
    $self->{resp} = $self->ua_get($get_url);
    $self->{tree} = HTML::TreeBuilder::XPath->new_from_content($self->{resp}->decoded_content);

    my $test_components_record = {userTestId => $test_id};
    if ($test->{testName} =~ m/^XR/ || $test->{testName} =~ m/^CT/) {
        $test_components_record->{testType} = 'imaging';
    } else {
        $test_components_record->{testType} = 'lab';
    }

    $self->do_components($test_components_record);
    $self->do_narrative($test_components_record);
    $self->do_impression($test_components_record);
    $self->do_general($test_components_record);

    $self->add_test_components($test_components_record);
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

        my $start_date;                                             # XXX
        my $end_date;                                               # XXX
        my $status;                                                 # XXX

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
                           reporteedDate => undef,
                          });
    }
}

sub do_immunizations {
    my ($self) = @_;

    my $immunizations = $self->{tree}->findnodes('/html/body//div[@id="immunizationform"]/div/table//tr');
    foreach my $immunization (@$immunizations) {
        my @tds = $immunization->look_down('_tag', 'td');
        next if (scalar(@tds) != 2);
        my $kind      = $tds[0]->as_trimmed_text;
        my $done_date = $tds[1]->as_trimmed_text;
        my @done_date = split("/", $done_date);

        $self->add_immunization({
                                 immunizationName      => $kind,
                                 dueDateOrTimeFrame      => undef,
                                 doneDate      => sprintf("%d-%02d-%02d", $done_date[2], $done_date[0], $done_date[1]),
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
                                    diagnosisDateOrTimeFrame => $date, # XXX why varchar ??? (age 16)
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
                                    diagnosisDateOrTimeFrame => $date, # XXX why varchar ??? (age 16)
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

# select provider from providers table using available data
# XXX providers table has no unique aside from the primary key (id)
# XXX email and emailHash were made optional
#
sub get_provider_id {
    my ($self, $data) = @_;

    my $providers;
    if (defined($data->{fullName})) {
        $providers = $self->{dbh}->selectall_hashref("select * from providers where fullName=?", "id", {},$data->{fullName});
    }

    if (defined($providers) && scalar(keys %$providers) == 1) {
        my @ids = keys %$providers;
        return $ids[0];
    }
    return undef;
}

sub get_test_id {
    my ($self, $data) = @_;

    my $tests;
    $tests = $self->{dbh}->selectall_hashref("select * from user_tests where testName=? and dateOrdered=? and providerId=?", "id", {},
                                             $data->{testName}, $data->{dateOrdered}, $data->{providerId});

    if (defined($tests) && scalar(keys %$tests) == 1) {
        my @ids = keys %$tests;
        return $ids[0];
    }
    return undef;
}

sub upsert_provider {
    my ($self, $data) = @_;
    my $sth;

    my $provider_id = $self->get_provider_id($data);
    return $provider_id if (defined($provider_id));

    $sth = $self->{dbh}->prepare("insert into providers(" .
                                 "status, email, emailHash, firstName, lastName, fullName, photo, address1, address2, city, state, zipcode, " .
                                 "timeZone, updated, created" .
                                 ") " .
                                 "values(" .
                                 "?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, " .
                                 "?, ?, ?" .
                                 ")");
    $sth->bind_param(1,   'A');                   # XXX always active?
    $sth->bind_param(2,   $data->{email});
    $sth->bind_param(3,   undef);
    $sth->bind_param(4,   $data->{firstName});
    $sth->bind_param(5,   $data->{lastName});
    $sth->bind_param(6,   $data->{fullName});
    $sth->bind_param(7,   $data->{photo});
    $sth->bind_param(8,   $data->{address1});
    $sth->bind_param(9,   $data->{address2});
    $sth->bind_param(10,  $data->{city});
    $sth->bind_param(11,  $data->{state});
    $sth->bind_param(12,  $data->{zipcode});

    $sth->execute;
    return $sth->{mysql_insertid};
}

sub upsert_test {
    my ($self, $data) = @_;
    my $sth;

    my $provider_id = $self->get_test_id($data);
    return $provider_id if (defined($provider_id));

    $sth = $self->{dbh}->prepare("insert into user_tests(" .
                                    "userId, ehrEntityId," .
                                    "testName, dateOrdered, providerId" .
                                    ") " .
                                    "values(" .
                                    "?, ?, ?, ?, ?" .
                                    ")");


    $sth->bind_param(1,  $self->{user_id});
    $sth->bind_param(2,  $self->{ehr_entity_id});
    $sth->bind_param(3,  $data->{testName});
    $sth->bind_param(4,  $data->{dateOrdered});
    $sth->bind_param(5,  $data->{providerId});

    $sth->execute;
    return $sth->{mysql_insertid};
}

sub add_medication {
    my ($self, $data) = @_;

    # keep number of attributes in sync with the schema user_medication_history
    die "Invalid user_medication_history object.  Incorrect number of keys" if (scalar(keys %$data) != 8);

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

sub add_allergy {
    my ($self, $data) = @_;

    # keep number of attributes in sync with the schema user_allergies
    die "Invalid user_allergies object.  Incorrect number of keys" if (scalar(keys %$data) != 4);

    my $sth = $self->{dbh}->prepare("insert into user_allergies(" .
                                    "userId, ehrEntityId," .
                                    "allergen, reaction, severity, reportedDate" .
                                    ") " .
                                    "values(" .
                                    "?, ?, ?, ?, ?, ?" .
                                    ")");
    $sth->bind_param(1,  $self->{user_id});
    $sth->bind_param(2,  $self->{ehr_entity_id});
    $sth->bind_param(3,  $data->{allergen});
    $sth->bind_param(4,  $data->{reaction});
    $sth->bind_param(5,  $data->{severity});
    $sth->bind_param(6,  $data->{reportedDate});

    $sth->execute;
}

sub add_immunization {
    my ($self, $data) = @_;

    # keep number of attributes in sync with the schema user_immunizations
    die "Invalid user_immunizations object.  Incorrect number of keys" if (scalar(keys %$data) != 3);

    my $sth = $self->{dbh}->prepare("insert into user_immunizations(" .
                                    "userId, ehrEntityId," .
                                    "immunizationName, dueDateOrTimeFrame, doneDate" .
                                    ") " .
                                    "values(" .
                                    "?, ?, ?, ?, ?" .
                                    ")");
    $sth->bind_param(1,  $self->{user_id});
    $sth->bind_param(2,  $self->{ehr_entity_id});
    $sth->bind_param(3,  $data->{immunizationName});
    $sth->bind_param(4,  $data->{dueDateOrTimeFrame});
    $sth->bind_param(5,  $data->{doneDate});

    $sth->execute;
}

sub add_medical_history {
    my ($self, $data) = @_;

    # keep number of attributes in sync with the schema user_medical_history
    die "Invalid user_medical_history object.  Incorrect number of keys" if (scalar(keys %$data) != 5);

    my $sth = $self->{dbh}->prepare("insert into user_medical_history(" .
                                    "userId, ehrEntityId," .
                                    "historyType, relationship, diagnosis, diagnosisDateOrTimeFrame, comments" .
                                    ") " .
                                    "values(" .
                                    "?, ?, ?, ?, ?, ?, ?" .
                                    ")");
    $sth->bind_param(1,  $self->{user_id});
    $sth->bind_param(2,  $self->{ehr_entity_id});
    $sth->bind_param(3,  $data->{historyType});
    $sth->bind_param(4,  $data->{relationship});
    $sth->bind_param(5,  $data->{diagnosis});
    $sth->bind_param(6,  $data->{diagnosisDateOrTimeFrame});
    $sth->bind_param(7,  $data->{comments});

    $sth->execute;
}

sub add_tests {
    my ($self, $data) = @_;

    # keep number of attributes in sync with the schema user_medical_history
    die "Invalid user_tests object.  Incorrect number of keys" if (scalar(keys %$data) != 3);

    my $sth = $self->{dbh}->prepare("insert into user_tests(" .
                                    "userId, ehrEntityId," .
                                    "testName, dateOrdered, providerId" .
                                    ") " .
                                    "values(" .
                                    "?, ?, ?, ?, ?" .
                                    ")");
    $sth->bind_param(1,  $self->{user_id});
    $sth->bind_param(2,  $self->{ehr_entity_id});
    $sth->bind_param(3,  $data->{testName});
    $sth->bind_param(4,  $data->{dateOrdered});
    $sth->bind_param(5,  $data->{providerId});

    $sth->execute;

    return $sth->{mysql_insertid};
}

sub add_test_components {
    my ($self, $data) = @_;

    # keep number of attributes in sync with the schema user_medical_history
    die "Invalid user_test_components object.  Incorrect number of keys" if (scalar(keys %$data) != 13);

    my $sth = $self->{dbh}->prepare("insert into user_test_components(" .
                                    "userId, ehrEntityId," .
                                    "userTestId, testType, testComponentName, userValue, standardRange, units, flag, testComponentResult," .
                                    "dateSpecimenCollected, dateResultProvided, imagingNarrative, imagingImpression, providerId" .
                                    ") " .
                                    "values(" .
                                    "?, ?, ?, ?, ?,?, ?, ?, ?, ?,?, ?, ?, ?, ?" .
                                    ")");
    $sth->bind_param(1,  $self->{user_id});
    $sth->bind_param(2,  $self->{ehr_entity_id});
    $sth->bind_param(3,  $data->{userTestId});
    $sth->bind_param(4,  $data->{testType});
    $sth->bind_param(5,  $data->{testComponentName});
    $sth->bind_param(6,  $data->{userValue});
    $sth->bind_param(7,  $data->{standardRange});
    $sth->bind_param(8,  $data->{units});
    $sth->bind_param(9,  $data->{flag});
    $sth->bind_param(10,  $data->{testComponentResult});
    $sth->bind_param(11,  $data->{dateSpecimenCollected});
    $sth->bind_param(12,  $data->{dateResultProvided});
    $sth->bind_param(13,  $data->{imagingNarrative});
    $sth->bind_param(14,  $data->{imagingImpression});
    $sth->bind_param(15,  $data->{providerId});

    $sth->execute;
}

sub add_to_user_visits {
    my ($self, $data) = @_;

    # keep number of attributes in sync with the schema user_medical_history
    die "Invalid user_visits object.  Incorrect number of keys" if (scalar(keys %$data) != 5);

    my $sth = $self->{dbh}->prepare("insert into user_visits(" .
                                    "userId, ehrEntityId," .
                                    "description, visitDateTime, departmentOrClinic, providerType, dischargeDateTime" .
                                    ") " .
                                    "values(" .
                                    "?, ?, ?, ?, ?,?, ?" .
                                    ")");
    $sth->bind_param(1,  $self->{user_id});
    $sth->bind_param(2,  $self->{ehr_entity_id});
    $sth->bind_param(3,  $data->{description});
    $sth->bind_param(4,  $data->{visitDateTime});
    $sth->bind_param(5,  $data->{departmentOrClinic});
    $sth->bind_param(6,  $data->{providerType});
    $sth->bind_param(7,  $data->{dischargeDateTime});

    $sth->execute;

    return $sth->{mysql_insertid};
}

sub add_to_user_visit_details {
    my ($self, $data, $visit_detail_id) = @_;

    # keep number of attributes in sync with the schema user_visit_details
    die "Invalid user_visit_details object.  Incorrect number of keys" if (scalar(keys %$data) != 10);

    my $sth = $self->{dbh}->prepare("insert into user_visit_details(" .
                                    "userId, ehrEntityId,userVisitId," .
                                    "visitTimestamp,providerId,reasonForVisit,visitType,diagnosis,vitals,referrals,testsOrdered,surgery" .
                                    ") " .
                                    "values(" .
                                    "?, ?, ?,?, ?, ?,?, ?, ?,?, ?, ?" .
                                    ")");
    $sth->bind_param(1,  $self->{user_id});
    $sth->bind_param(2,  $self->{ehr_entity_id});
    $sth->bind_param(3,  $data->{userVisitId});
    $sth->bind_param(4,  $data->{visitTimestamp});
    $sth->bind_param(5,  $data->{providerId});
    $sth->bind_param(6,  $data->{reasonForVisit});
    $sth->bind_param(7,  $data->{visitType});
    $sth->bind_param(8,  $data->{diagnosis});
    $sth->bind_param(9,  $data->{vitals});
    $sth->bind_param(10,  $data->{referrals});
    $sth->bind_param(11,  $data->{testsOrdered});
    $sth->bind_param(12,  $data->{surgery});

    $sth->execute;

    return $sth->{mysql_insertid};
}

sub add_to_user_visit_diagnosis {
    my ($self, $records, $visit_detail_id) = @_;

    my $sth = $self->{dbh}->prepare("insert into user_visit_diagnosis(" .
                                    "userId, ehrEntityId,visitDetailId," .
                                    "description" .
                                    ") " .
                                    "values(" .
                                    "?, ?, ?, ?" .
                                    ")");

    foreach my $record (@$records) {
        # keep number of attributes in sync with the schema user_visit_diagnosis
        die "Invalid user_visit_diagnosis object.  Incorrect number of keys" if (scalar(keys %$record) != 1);

        $sth->bind_param(1,  $self->{user_id});
        $sth->bind_param(2,  $self->{ehr_entity_id});
        $sth->bind_param(3,  $visit_detail_id);
        $sth->bind_param(4,  $record->{description});

        $sth->execute;
    }
}

sub add_to_user_visit_tests {
    my ($self, $records, $visit_detail_id) = @_;

    my $sth = $self->{dbh}->prepare("insert into user_visit_tests(" .
                                    "userId, ehrEntityId,visitDetailId," .
                                    "userTestId" .
                                    ") " .
                                    "values(" .
                                    "?, ?, ?, ?" .
                                    ")");

    foreach my $record (@$records) {
        # keep number of attributes in sync with the schema user_visit_tests
        die "Invalid user_visit_tests object.  Incorrect number of keys" if (scalar(keys %$record) != 1);

        $sth->bind_param(1,  $self->{user_id});
        $sth->bind_param(2,  $self->{ehr_entity_id});
        $sth->bind_param(3,  $visit_detail_id);
        $sth->bind_param(4,  $record->{userTestId});

        $sth->execute;
    }
}

sub add_to_user_visit_surgeries {
    my ($self, $records, $visit_detail_id) = @_;


    my $sth = $self->{dbh}->prepare("insert into user_visit_surgeries(" .
                                    "userId, ehrEntityId,visitDetailId," .
                                    "primaryProcedure, dateTimePerformed,providerID,location,status" .
                                    ") " .
                                    "values(" .
                                    "?, ?, ?, ?, ?,?, ?,?" .
                                    ")");

    foreach my $record (@$records) {
        # keep number of attributes in sync with the schema user_visit_surgeries
        die "Invalid user_visit_surgeries object.  Incorrect number of keys" if (scalar(keys %$record) != 5);

        $sth->bind_param(1,  $self->{user_id});
        $sth->bind_param(2,  $self->{ehr_entity_id});
        $sth->bind_param(3,  $visit_detail_id);
        $sth->bind_param(4,  $record->{primaryProcedure});
        $sth->bind_param(5,  $record->{dateTimePerformed});
        $sth->bind_param(6,  $record->{providerId});
        $sth->bind_param(7,  $record->{location});
        $sth->bind_param(8,  $record->{status});

        $sth->execute;
    }
}

1;
