use HTTP::Daemon;
use Proc::Background;
use PHR;

my $PORT = 9080;

my $serv = HTTP::Daemon->new(LocalPort => $PORT, 
                             Reuse => 1);
print "listening on: $PORT" ;
my $background_tasks = {};

sleep(4);
while(my $conn = $serv->accept) {
    while (my $req = $conn->get_request) {
        if ($req->uri->path =~ m/\/scrape\/([^\/]+)\/([^\/]+)/) {
            my $user_email = $1;
            my $ehr_entity = $2;
            my %query_form = $req->uri->query_form;

            eval {
                if ($query_form{bg}) {
                    # no exceptions, done if foreground.
                    my $proc = $background_tasks->{$user_email . '@' . $ehr_entity};
                    if (!defined($proc) || !$proc->alive) {
                        $background_tasks->{$user_email . '@' . $ehr_entity} = Proc::Background->new("/home/pkeni/git/phr/perl/phr.pm", $user_email, $ehr_entity);
                    }
                } else {
                    PHR->scrape_for_user_ehr_entity($user_email, $ehr_entity);
                }
                # no exceptions, done if foreground.
                $conn->send_status_line(200, "Done");
            } || do {
                my $err = $@;
                $conn->send_status_line(500, $err);
            };
            $conn->close;
        }
    }
}
