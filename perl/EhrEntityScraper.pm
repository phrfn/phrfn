package EhrEntityScraper;

use strict;
use warnings;
use DBI;
use File::Path qw(make_path);
use URI::Escape;
use HTTP::Cookies;
use HTML::TreeBuilder;
use HTTP::Response;
use HTML::TreeBuilder::XPath;

sub new {
    my ($class, $args_hash) = @_;
    my $self = bless {}, $class;
    $self->initialize($args_hash);
    return $self;
}

sub canned_config {
    my ($self) = @_;

    return {
            save_to_canned   => $self->{save_to_canned},
            read_from_canned => $self->{read_from_canned},
           };
}

sub set_canned_config {
    my ($self, $config) = @_;

    $self->{save_to_canned}  = $config->{save_to_canned};
    $self->{read_from_canned}= $config->{read_from_canned};
}

sub initialize {
    my ($self, $args_hash) = @_;

    @$self{keys %$args_hash} = values %$args_hash;
    $self->{dbh} = DBI->connect ('dbi:mysql:database=phr', 'root', 'root', {RaiseError => 1, AutoCommit => 1});

    $self->set_canned_config({save_to_canned => defined($args_hash->{save_to_canned})? $args_hash->{save_to_canned} : 0,
                              read_from_canned => defined($args_hash->{read_from_canned})? $args_hash->{read_from_canned} : 0});

    $self->{canned_dir}      = "/var/tmp/canned-ehr-entity-scraper";
    $self->{cookie_dir}      = "/var/tmp/cookies-ehr-entity-scraper";
    $self->initialize_canned_dir();
    $self->initialize_cookie_dir();

    $self->{ua}  = new LWP::UserAgent(agent => 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/535.1 (KHTML, like Gecko) Ubuntu/10.10 ' . 
                                      'Chromium/14.0.808.0 Chrome/14.0.808.0 Safari/535.1');
    push @{$self->{ua}->requests_redirectable}, 'POST';
    $self->{ua}->cookie_jar(HTTP::Cookies->new(file => "$self->{cookie_dir}/cookies.lwp",
                                               autosave => 1,
                                               ignore_discard => 1,));

}

sub initialize_canned_dir {
    my ($self) = @_;
    make_path($self->{canned_dir});
}

sub initialize_cookie_dir {
    my ($self) = @_;
    make_path($self->{cookie_dir});
}

sub read_bytes_from_file {
    my ($self, $file_name) = @_;

    local $/ = undef;
    open FILE, $file_name or die "Couldn't open response file";
    binmode FILE;
    my $ret = <FILE>;
    close FILE;
    return $ret;
}

sub make_name_values {
    my ($self, $input_nodes, $override_params) = @_;
    my $ret = {};

    for (my $i = 0; $i < scalar(@$input_nodes); $i++) {
        my $input_node = $input_nodes->[$i];
        my $input_name = $input_node->attr('name');
        next if (!defined($input_name));
        $ret->{$input_name} = exists($override_params->{$input_name}) ? $override_params->{$input_name} : $input_node->attr('value');
    }
    return $ret;
}

sub ua_post {
    my ($self, $url, $post_params) = @_;
    my $resp;

    if ($self->{read_from_canned}) {
        $resp = $self->read_from_canned("POST", $url, $post_params);
        return $resp if(defined($resp));
    }

    $resp = $self->{ua}->post($url, $post_params);
    die "post failed. url: $url post_params: $post_params" if (!$resp->is_success);
    if ($self->{save_to_canned}) {
        $self->save_to_canned($url, $resp);
    }
    return $resp;
}

sub ua_get {
    my ($self, $url, $get_params) = @_;

    my $resp;
    if ($self->{read_from_canned}) {
        $resp = $self->read_from_canned("GET", $url, $get_params);
        return $resp if(defined($resp));
    }

    $resp = $self->{ua}->get($url);
    die "get failed. url = $url" if (!$resp->is_success);
    if ($self->{save_to_canned}) {
        $self->save_to_canned($url, $resp);
    }
    return $resp;
}

sub read_from_canned {
    my ($self, $method, $url, $get_args) = @_;
    my $escaped_url = uri_escape($url);

    my $fh;

    $fh = IO::File->new ("< $self->{canned_dir}/$escaped_url/code");
    return undef if (!defined($fh));
    my $code =  <$fh>;
    $fh->close;

    $fh = IO::File->new ("< $self->{canned_dir}/$escaped_url/message");
    return undef if (!defined($fh));
    my $message =  <$fh>;
    $fh->close;

    $fh = IO::File->new ("< $self->{canned_dir}/$escaped_url/headers");
    return undef if (!defined($fh));
    my $headers = HTTP::Headers->new();
    while(my $line = readline($fh)) {
        if ($line =~ m/([^:]+):\s+(.*)/) {
            $headers->header($1 => $2)
        }
    }
    $fh->close;

    my $content = $self->read_bytes_from_file("$self->{canned_dir}/$escaped_url/content");

    my $resp = HTTP::Response->new($code, $message, $headers, $content);
    $resp->request(HTTP::Request->new($method => $url));
    return $resp;
}

sub save_to_canned {
    my ($self, $url, $resp) = @_;
    my $escaped_url = uri_escape($url);
    make_path("$self->{canned_dir}/$escaped_url");

    my $fh = undef;

    $fh = IO::File->new ("> $self->{canned_dir}/$escaped_url/code") or die "no code file";
    print $fh $resp->code;
    $fh->close;

    $fh = IO::File->new ("> $self->{canned_dir}/$escaped_url/message") or die "no message file";
    print $fh $resp->message;
    $fh->close;

    $fh = IO::File->new ("> $self->{canned_dir}/$escaped_url/headers") or die "no headers file";
    print $fh $resp->headers->as_string;
    $fh->close;

    $fh = IO::File->new ("> $self->{canned_dir}/$escaped_url/content") or die "no content file";
    print $fh $resp->content;
    $fh->close;
}

sub scrape {
    my ($self) = @_;

    $self->login();
    $self->health_summary();
    $self->medical_history();
    $self->appointments();
    $self->tests();
    $self->visits();
    $self->postprocess();
}

sub login {
    my $self = shift;

    my $form = $self->get_login_form();
    my $post_url = URI->new_abs($form->[0]->attr('action'), $self->{login_page}->base());
    my @inputs = $form->[0]->look_down("_tag", "input");
    my $post_params = $self->make_name_values(\@inputs, {
                                                         Login     => $self->{ehr_entity_user},
                                                         Password  => $self->{ehr_entity_pass},
                                                         jsenabled => 1,
                                                         'submit' => 'Sign In',
                                                       });
    # always perform real login regardless of canned config
    # my $saved_canned_config = $self->canned_config();
    # $self->set_canned_config({save_to_canned => 0, read_from_canned => 0});
    $self->{resp} = $self->ua_post($post_url, $post_params);
    # $self->set_canned_config($saved_canned_config);
}

#
# sometimes you need to get the login page twice to get the right form
# 
sub get_login_form {
    my $self = shift;
    my ($form, $action);

    $self->{login_page} = $self->ua_get($self->{ehr_entity_url});
    $self->{tree} = HTML::TreeBuilder::XPath->new_from_content($self->{login_page}->decoded_content);
    $form = $self->{tree}->findnodes('/html/body//div[@id="defaultForm"]/form');
    $action = (defined($form) && defined($form->[0])) ? $form->[0]->attr('action') : undef;
    if (!defined($form) || !defined($action)) {
        $form = $action = undef;
        $self->{login_page} = $self->ua_get($self->{ehr_entity_url});
        $self->{tree} = HTML::TreeBuilder::XPath->new_from_content($self->{login_page}->decoded_content);
        $form = $self->{tree}->findnodes('/html/body//div[@id="defaultForm"]/form');
        $action = (defined($form) && defined($form->[0])) ? $form->[0]->attr('action') : undef;
        if (!defined($form) || !defined($action)) {
            die "could not get login page";
        }
    }
    return $form;
}

sub health_summary {
    my $self = shift;
    my $get_url = URI->new_abs("./inside.asp?mode=snapshot", $self->{ehr_entity_url});

    $self->{resp} = $self->ua_get($get_url);
    $self->{tree} = HTML::TreeBuilder::XPath->new_from_content($self->{resp}->decoded_content);

    $self->do_medications();
    $self->do_allergies();
    $self->do_immunizations();
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

sub postprocess {
}

1;
