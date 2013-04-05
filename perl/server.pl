use PHR;
use HTTP::Daemon;
use threads;
use URI;

my $PORT = 9080;
my $background_tasks = {};

my $d = HTTP::Daemon->new(LocalAddr => 'localhost', #$ARGV[0],
                          LocalPort => 9080, # 80,
                          Reuse => 1,
                          Listen => 20) || die $!;
print "Web Server started, server address: ", $d->sockhost(), ", server port: ", $d->sockport(), "\n";

while (my $c = $d->accept) {
    process_client_requests($c);
}

sub process_client_requests {
    my $c = shift;
    my $r = $c->get_request;

    if (defined($r)) {
        if ($r->method eq "GET") {
            my $path = $r->url->path();
            if ($path =~ m/\/scrape\/([^\/]+)\/([^\/]+)/) {
                my $email = $1;
                my $ehre = $2;
                my %qf = URI->new($r->uri)->query_form;

                eval {
                    if (!defined($qf{bg})) {
                        PHR->scrape_for_user_ehr_entity($email, $ehre);
                    } else {
                        system("./PHR.pm $email $ehre > /var/tmp/PHR_${email}_${ehre}.log 2>&1 &");
                    }
                    $c->send_status_line(200);
                };
                if ($@) {
                    $c->send_status_line(500);
                }
                ;
            }
        } else {
            print "unknown method ".$r->method."\n";
        }
    }
    $c->close if (defined($c));
}
