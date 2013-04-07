#!/usr/bin/perl
use strict;
use warnings;
use LWP::UserAgent;
use HTML::TreeBuilder;
use HTTP::Response;
use HTML::TreeBuilder::XPath;
use URI;

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

sub upsert_provider {
    my ($self, $data) = @_;
    my $sth;

    my $provider_id = $self->get_provider_id($data);

    $sth = $self->{dbh}->prepare("insert into providers(" .
                                 "status, email, emailHash, firstName, lastName, fullName, sex, photo, address1, address2, city, state, zipcode, " .
                                 "timeZone, phone, specialty, language " .
                                 ") " .
                                 "values(" .
                                 "?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?" .
                                 ") on duplicate key update status=?, email=?, emailHash=?, " .
                                 "firstName=?, lastName=?, fullName=?, sex=?, " .
                                 "photo=?, address1=?, address2=?, city=?, " . 
                                 "state=?, zipcode=?, timeZone=?, phone=?, " .
                                 "specialty=?, language=?");
    $sth->bind_param(1,   'A');
    $sth->bind_param(2,   $data->{email});
    $sth->bind_param(3,   undef);
    $sth->bind_param(4,   $data->{firstName});
    $sth->bind_param(5,   $data->{lastName});
    $sth->bind_param(6,   $data->{fullName});
    $sth->bind_param(7,   $data->{sex});
    $sth->bind_param(8,   $data->{photo});
    $sth->bind_param(9,   $data->{address1});
    $sth->bind_param(10,   $data->{address2});
    $sth->bind_param(11,  $data->{city});
    $sth->bind_param(12,  $data->{state});
    $sth->bind_param(13,  $data->{zipcode});
    $sth->bind_param(14,  $data->{timeZone});
    $sth->bind_param(15,  $data->{phone});
    $sth->bind_param(16,  $data->{specialty});
    $sth->bind_param(17,  $data->{language});
    $sth->bind_param(18,   'A');
    $sth->bind_param(19,   $data->{email});
    $sth->bind_param(20,   undef);
    $sth->bind_param(21,   $data->{firstName});
    $sth->bind_param(22,   $data->{lastName});
    $sth->bind_param(23,   $data->{fullName});
    $sth->bind_param(24,   $data->{sex});
    $sth->bind_param(25,   $data->{photo});
    $sth->bind_param(26,   $data->{address1});
    $sth->bind_param(27,   $data->{address2});
    $sth->bind_param(28,  $data->{city});
    $sth->bind_param(29,  $data->{state});
    $sth->bind_param(30,  $data->{zipcode});
    $sth->bind_param(31,  $data->{timeZone});
    $sth->bind_param(32,  $data->{phone});
    $sth->bind_param(33,  $data->{specialty});
    $sth->bind_param(34,  $data->{language});

    $sth->execute;

    if (defined($provider_id)) {
        return $provider_id;
    } else {
        return $sth->{mysql_insertid};
    }
}

sub get_test_id {
    my ($self, $data) = @_;

    my $tests;
    $tests = $self->{dbh}->selectall_hashref("select * from user_tests where userId=? and ehrEntityId=? and testName=? and dateOrdered=? and providerId=?",
                                             "id", {}, $self->{user_id}, $self->{ehr_entity_id}, $data->{testName}, $data->{dateOrdered},
                                             $data->{providerId});

    if (defined($tests) && scalar(keys %$tests) == 1) {
        my @ids = keys %$tests;
        return $ids[0];
    }
    return undef;
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
                                    ") on duplicate key update userId=?");
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
    $sth->bind_param(11,  $self->{user_id});

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
                                    ") on duplicate key update userId=?");
    $sth->bind_param(1,  $self->{user_id});
    $sth->bind_param(2,  $self->{ehr_entity_id});
    $sth->bind_param(3,  $data->{allergen});
    $sth->bind_param(4,  $data->{reaction});
    $sth->bind_param(5,  $data->{severity});
    $sth->bind_param(6,  $data->{reportedDate});
    $sth->bind_param(7,  $self->{user_id});

    $sth->execute;
}

sub add_health_reminder {
    my ($self, $data) = @_;

    # keep number of attributes in sync with the schema user_health_reminders
    die "Invalid user_reminders object.  Incorrect number of keys" if (scalar(keys %$data) != 4);

    my $sth = $self->{dbh}->prepare("insert into user_health_reminders(" .
                                    "userId, ehrEntityId," .
                                    "reminderName, dueDateOrTimeFrame, doneDate, status" .
                                    ") " .
                                    "values(" .
                                    "?, ?, ?, ?, ?, ?" .
                                    ") on duplicate key update userId=?");
    $sth->bind_param(1,  $self->{user_id});
    $sth->bind_param(2,  $self->{ehr_entity_id});
    $sth->bind_param(3,  $data->{reminderName});
    $sth->bind_param(4,  $data->{dueDateOrTimeFrame});
    $sth->bind_param(5,  $data->{doneDate});
    $sth->bind_param(6,  $data->{status});
    $sth->bind_param(7,  $self->{user_id});

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
                                    ") on duplicate key update userId=?");
    $sth->bind_param(1,  $self->{user_id});
    $sth->bind_param(2,  $self->{ehr_entity_id});
    $sth->bind_param(3,  $data->{immunizationName});
    $sth->bind_param(4,  $data->{dueDateOrTimeFrame});
    $sth->bind_param(5,  $data->{doneDate});
    $sth->bind_param(6,  $self->{user_id});

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
                                    ") on duplicate key update userId=?");
    $sth->bind_param(1,  $self->{user_id});
    $sth->bind_param(2,  $self->{ehr_entity_id});
    $sth->bind_param(3,  $data->{historyType});
    $sth->bind_param(4,  $data->{relationship});
    $sth->bind_param(5,  $data->{diagnosis});
    $sth->bind_param(6,  $data->{diagnosisDateOrTimeFrame});
    $sth->bind_param(7,  $data->{comments});
    $sth->bind_param(8,  $self->{user_id});

    $sth->execute;
}

sub add_test_components {
    my ($self, $data) = @_;

    # keep number of attributes in sync with the schema user_medical_history
    die "Invalid user_test_components object.  Incorrect number of keys" if (scalar(keys %$data) != 8);

    foreach my $component (@{$data->{components}}) {
        my $sth = $self->{dbh}->prepare("insert into user_test_components(" .
                                        "userId, ehrEntityId," .
                                        "userTestId, testType, testComponentName, userValue, standardRange, units, flag, testComponentResult," .
                                        "dateSpecimenCollected, dateResultProvided, imagingNarrative, imagingImpression, providerId" .
                                        ") " .
                                        "values(" .
                                        "?, ?, ?, ?, ?,?, ?, ?, ?, ?,?, ?, ?, ?, ?" .
                                        ") on duplicate key update userId=?");
        $sth->bind_param(1,  $self->{user_id});
        $sth->bind_param(2,  $self->{ehr_entity_id});
        $sth->bind_param(3,  $data->{userTestId});

        $sth->bind_param(4,  $data->{testType});

        $sth->bind_param(5,  $component->{testComponentName});
        $sth->bind_param(6,  $component->{userValue});
        $sth->bind_param(7,  $component->{standardRange});
        $sth->bind_param(8,  $component->{units});
        $sth->bind_param(9,  $component->{flag});
        $sth->bind_param(10, $component->{testComponentResult});

        $sth->bind_param(11,  $data->{dateSpecimenCollected});
        $sth->bind_param(12,  $data->{dateResultProvided});
        $sth->bind_param(13,  $data->{imagingNarrative});
        $sth->bind_param(14,  $data->{imagingImpression});
        $sth->bind_param(15,  $data->{providerId});
        $sth->bind_param(16,  $self->{user_id});

        $sth->execute;
    }
}

sub get_visit_id {
    my ($self, $data) = @_;

    my $visits;
    $visits = $self->{dbh}->selectall_hashref("select * from user_visits where userId=? and ehrEntityId=? and visitDateTime=? and departmentOrClinic=?", 
                                             "id", {}, $self->{user_id}, $self->{ehr_entity_id}, $data->{visitDateTime}, $data->{departmentOrClinic});

    if (defined($visits) && scalar(keys %$visits) == 1) {
        my @ids = keys %$visits;
        return $ids[0];
    }
    return undef;
}

sub upsert_user_visit {
    my ($self, $data) = @_;

    my $visit_id = $self->get_visit_id($data);
    return $visit_id if (defined($visit_id));

    # keep number of attributes in sync with the schema user_medical_history
    die "Invalid user_visits object.  Incorrect number of keys" if (scalar(keys %$data) != 5);

    my $sth = $self->{dbh}->prepare("insert into user_visits(" .
                                    "userId, ehrEntityId," .
                                    "description, visitDateTime, departmentOrClinic, providerType, dischargeDateTime" .
                                    ") " .
                                    "values(" .
                                    "?, ?, ?, ?, ?,?, ?" .
                                    ") on duplicate key update userId=?");
    $sth->bind_param(1,  $self->{user_id});
    $sth->bind_param(2,  $self->{ehr_entity_id});
    $sth->bind_param(3,  $data->{description});
    $sth->bind_param(4,  $data->{visitDateTime});
    $sth->bind_param(5,  $data->{departmentOrClinic});
    $sth->bind_param(6,  $data->{providerType});
    $sth->bind_param(7,  $data->{dischargeDateTime});
    $sth->bind_param(8,  $self->{user_id});

    $sth->execute;
    return $sth->{mysql_insertid};
}

sub get_visit_detail_id {
    my ($self, $data) = @_;

    my $visit_details;
    $visit_details = 
      $self->{dbh}->selectall_hashref(
         "select * from user_visit_details where userId=? and ehrEntityId=? and userVisitId=? and visitTimestamp=? and providerId=?",
                                      "id", {}, $self->{user_id}, $self->{ehr_entity_id}, $data->{userVisitId}, $data->{visitTimestamp},
                                      $data->{providerId});

    if (defined($visit_details) && scalar(keys %$visit_details) == 1) {
        my @ids = keys %$visit_details;
        return $ids[0];
    }
    return undef;
}

sub upsert_visit_detail {
    my ($self, $data) = @_;

    my $visit_detail_id = $self->get_visit_detail_id($data);
    return $visit_detail_id if (defined($visit_detail_id));

    # keep number of attributes in sync with the schema user_visit_details
    die "Invalid user_visit_details object.  Incorrect number of keys" if (scalar(keys %$data) != 10);

    my $sth = $self->{dbh}->prepare("insert into user_visit_details(" .
                                    "userId, ehrEntityId,userVisitId," .
                                    "visitTimestamp,providerId,reasonForVisit,visitType,diagnosis,vitals,referrals,testsOrdered,surgery" .
                                    ") " .
                                    "values(" .
                                    "?, ?, ?,?, ?, ?,?, ?, ?,?, ?, ?" .
                                    ") on duplicate key update userId=?");
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
    $sth->bind_param(13,  $self->{user_id});

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
                                    ") on duplicate key update userId=?");

    foreach my $record (@$records) {
        # keep number of attributes in sync with the schema user_visit_diagnosis
        die "Invalid user_visit_diagnosis object.  Incorrect number of keys" if (scalar(keys %$record) != 1);

        $sth->bind_param(1,  $self->{user_id});
        $sth->bind_param(2,  $self->{ehr_entity_id});
        $sth->bind_param(3,  $visit_detail_id);
        $sth->bind_param(4,  $record->{description});
        $sth->bind_param(5,  $self->{user_id});

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
                                    ") on duplicate key update userId=?");

    foreach my $record (@$records) {
        # keep number of attributes in sync with the schema user_visit_tests
        die "Invalid user_visit_tests object.  Incorrect number of keys" if (scalar(keys %$record) != 1);

        $sth->bind_param(1,  $self->{user_id});
        $sth->bind_param(2,  $self->{ehr_entity_id});
        $sth->bind_param(3,  $visit_detail_id);
        $sth->bind_param(4,  $record->{userTestId});
        $sth->bind_param(5,  $self->{user_id});

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
                                    ") on duplicate key update userId=?");

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
        $sth->bind_param(9,  $self->{user_id});

        $sth->execute;
    }
}

sub add_to_user_visit_vitals {
    my ($self, $records, $visit_detail_id) = @_;


    my $sth = $self->{dbh}->prepare("insert into user_visit_vitals(" .
                                    "userId, ehrEntityId,visitDetailId," .
                                    "vitalName, vitalValue" .
                                    ") " .
                                    "values(" .
                                    "?, ?, ?, ?, ?" .
                                    ") on duplicate key update userId=?");

    foreach my $record (@$records) {
        # keep number of attributes in sync with the schema user_visit_vitals
        die "Invalid user_visit_surgeries object.  Incorrect number of keys" if (scalar(keys %$record) != 2);

        $sth->bind_param(1,  $self->{user_id});
        $sth->bind_param(2,  $self->{ehr_entity_id});
        $sth->bind_param(3,  $visit_detail_id);
        $sth->bind_param(4,  $record->{vitalName});
        $sth->bind_param(5,  $record->{vitalValue});
        $sth->bind_param(6,  $self->{user_id});

        $sth->execute;
    }
}

sub add_to_user_visit_referrals {
    my ($self, $records, $visit_detail_id) = @_;


    my $sth = $self->{dbh}->prepare("insert into user_visit_referrals(" .
                                    "userId, ehrEntityId,visitDetailId," .
                                    "referralInstructions" .
                                    ") " .
                                    "values(" .
                                    "?, ?, ?, ?" .
                                    ") on duplicate key update userId=?");

    foreach my $record (@$records) {
        # keep number of attributes in sync with the schema user_visit_referrals
        die "Invalid user_visit_referrals object.  Incorrect number of keys" if (scalar(keys %$record) != 2);

        $sth->bind_param(1,  $self->{user_id});
        $sth->bind_param(2,  $self->{ehr_entity_id});
        $sth->bind_param(3,  $visit_detail_id);
        $sth->bind_param(4,  $record->{referralInstructions});
        $sth->bind_param(5,  $self->{user_id});

        $sth->execute;
    }
}

1;
