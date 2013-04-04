#!/usr/bin/perl

my $month_map = {
                 "January" => "01",
                 "February" => "02",
                 "March" => "03",
                 "April" => "04",
                 "May" => "05",
                 "June" => "06",
                 "July" => "07",
                 "August" => "08",
                 "September" => "09",
                 "October" => "10",
                 "November" => "11",
                 "December" => "12",
                };


sub space_datetime {
    my ($str, $regex) = @_;

    my ($hour, $minutes, $ampm) = (0, 0, "AM");
    my ($month, $day, $year) = (1, 1, 1970);

    if ($str =~ m/\w+\s+(\w+)\s+(\d+), (\d+)\s*(\d+)?:?(\d+)?\s*(AM|PM)?/) {
        my ($month, $day, $year) = ($1, $2, $3);
        $hour = trim_undef($4) if (defined($4));
        $minutes = trim_undef($5) if (defined($5));
        $ampm = trim_undef($6) if (defined($6));

        $hour += 12 if (defined($ampm) && $ampm eq "PM");

        if ($day < 10)     {$day     = sprintf("%02d", $day);}
        if ($hour < 10)    {$hour    = sprintf("%02d", $hour);}
        if ($minutes < 10) {$minutes = sprintf("%02d", $minutes);}

        return "$year" . "-" . $month_map->{$month} . "-" . $day . " " . $hour . ":" . $minutes . ":00";
    } else {
        print "failed to parse timestamp.";
        return undef;
    }
    return undef;
}

sub forward_slash_datetime {
    my ($str, $regex) = @_;

    my ($hour, $minutes, $ampm) = (0, 0, "AM");
    my ($month, $day, $year);

    if ($str =~ m/(\d+)\/(\d+)\/(\d+)\s*(\d+)?:?(\d+)?\s*(AM|PM)?/) {
        ($month, $day, $year) = ($1, $2, $3);
        $hour = trim_undef($4) if (defined($4));
        $minutes = trim_undef($5) if (defined($5));
        $ampm = trim_undef($6) if (defined($6));

        $hour += 12 if (defined($ampm) && $ampm eq "PM");

        if ($month < 10)   {$month   = sprintf("%02d", $month);}
        if ($day < 10)     {$day     = sprintf("%02d", $day);}
        if ($hour < 10)    {$hour    = sprintf("%02d", $hour);}
        if ($minutes < 10) {$minutes = sprintf("%02d", $minutes);}

        return "$year" . "-" . $month . "-" . $day . " " . $hour . ":" . $minutes . ":00";
    } else {
        print "failed to parse timestamp.";
        return undef;
    }
    return undef;
    return make_timestamp(@_, "");
}

sub parse_visit_type {
    my ($str) = @_;
    if ($str =~ m/\d+\/\d+\/\d+ \d+:\d+\s*(AM|PM)\s*(.*)/) {
        my ($ampm, $visit_type) = ($1, $2);
        return trim_undef($visit_type);
    }
    return undef;
}

sub trim {
    my ($string) = @_;
    return undef if (!defined($string));
    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    $string =~ s/\240//g;
    return $string;
}

sub trim_undef {
    my ($string) = @_;

    my $ret = trim($string);
    return undef if (defined($ret) && length($ret) == 0);
    return $ret;
}

