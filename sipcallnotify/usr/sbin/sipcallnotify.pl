#!/usr/bin/perl
use utf8;
use Text::CSV;
binmode STDOUT, ":utf8";
use DBI;
use IO::Socket::INET;
use Proc::Daemon;
use Net::Address::IP::Local;
use Net::SIP::Leg;
use Net::SIP::Simple;
use Net::SIP::Simple::Call;
use Net::SIP::Simple::RTP;
use Config::Tiny;
use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init({ level => $DEBUG, utf8  => 1, });
$| = 1;

my $Config = Config::Tiny->new;
$Config = Config::Tiny->read( '/etc/sipcallnotify/main.conf', 'utf8' );

my $contacts = $Config->{_}->{contacts_csv_file};
my $blocked = $Config->{_}->{blacklist_csv_file};
my $logfile = $Config->{_}->{logfile};
my $provider = $Config->{_}->{provider};
my $domain = $Config->{_}->{domain};
my $user = $Config->{_}->{user};
my $pass = $Config->{_}->{pass};
my $header_caller_id = $Config->{_}->{caller_id_header};
my $tv = $Config->{_}->{notification_android_tv_ip};

my $local_address = Net::Address::IP::Local->public;

Proc::Daemon::Init;

my $continue = 1;
$SIG{TERM} = sub { $continue = 0 };

my $logconf = qq(
log4perl.rootLogger=INFO, LOGFILE
 
log4perl.appender.LOGFILE=Log::Log4perl::Appender::File
log4perl.appender.LOGFILE.filename=$logfile
log4perl.appender.LOGFILE.mode=append
 
log4perl.appender.LOGFILE.layout=PatternLayout
log4perl.appender.LOGFILE.layout.ConversionPattern=[%d] [%p %L]->  %m%n
);

Log::Log4perl::init( \$logconf );

my $log = Log::Log4perl::get_logger("My::SIPCallNotify");
$log->info("SIP Notifier and Blocker starting ...");

$log->debug("Initializing DB...");
my $dbh = DBI->connect("dbi:SQLite:dbname=:memory:","","",{ sqlite_unicode => 1 } );

$log->debug("Creating table people.");
$dbh->do("CREATE TABLE people (
   id     INTEGER PRIMARY KEY,
   name   VARCHAR(255),
   phone  VARCHAR(15)
)");
$log->debug("Create table blocked.");
$dbh->do("CREATE TABLE blocked (
   id     INTEGER PRIMARY KEY,
   phone  VARCHAR(15)
)");
$log->debug("DB initialization complete.");

my $csv = Text::CSV->new({ sep_char => ',' , quote_char => '"',  auto_diag => 1, binary => 1 });

$log->debug("Opening contacts file...");
open(my $data, '<:encoding(utf8)', $contacts) or $log->logdie("Could not open '$contacts'");
while (my $fields = $csv->getline( $data )) {
    my $name = $fields->[0];
    my $phones = $fields->[36].":::".$fields->[38].":::".$fields->[40];
    $phones =~ s/\s+//g;
    my @sp = split /:::/ , $phones;
    for my $phone (@sp) {
        $dbh->do("INSERT INTO people (name,phone) VALUES (?,?)", undef, $name,$phone);
    }
}
if (not $csv->eof) {
  $csv->error_diag();
}
close $data;
$log->debug("Contacts loaded.");

$log->debug("Opening block list...");
open(my $bdata, '<:encoding(utf8)', $blocked) or $log->logdie("Could not open '$blocked'");
while (my $fields = $csv->getline( $bdata )) {
    my $phone = $fields->[0];
    $phone =~ s/^\s+|\s+$//g;
    if ( substr($phone, 0, 1) ne "#" && $phone ne "" ){
        $dbh->do("INSERT INTO blocked (phone) VALUES (?)", undef, $phone);
    }
}
if (not $csv->eof) {
  $csv->error_diag();
}
close $bdata;
$log->debug("Block list loaded.");

$SIG{HUP}  = sub {
    $log->logdie("Terminating (got SIGHUP)...");
};
$SIG{TERM}  = sub {
    $log->logdie("Terminating (got SIGTERM)...");
};

##while ($continue) {

# create new socket and leg
$log->debug("Creating socket and leg with local address ".$local_address);
my $sock_tel_1 = IO::Socket::INET->new(LocalAddr => $local_address, PeerAddr => $provider, PeerPort => '5060', Proto => 'udp') or $log->logdie("Can't bind : $@");
my $leg_tel_1 = Net::SIP::Leg->new( sock => $sock_tel_1);
$log->debug("Socket and leg created.");

# create new agent
$log->debug("Creating agent.");
my $ua = Net::SIP::Simple->new(
    registrar => $provider,
    #domain => 'netpro.cl',
    domain => $domain,
    from => $user,
    leg => $leg_tel_1,
    auth => [$user,$pass] #user and password provided in the asterisk server
);
if ($ua->error){
    $log->error("agent:".$ua->error);
}
$log->debug("Agent created.");

#set my app
$log->debug("Creating app.");
my $receive = sub {
	 my ($endpoint,$ctx,$packet,$leg,$from) = @_;
	 if ( $packet->is_request and $packet->method eq 'INVITE' ) {
	    my $caller=$packet->get_header( $header_caller_id );

	    my $blk = $dbh->prepare("SELECT * from blocked where phone like ? limit 1");
	    my $brow = 0;
	    $blk->execute("%".$caller."%");
	    while (my $bh = $blk->fetchrow_arrayref) {
		$brow++;
	    }

	    if ($brow){
		#block this
	        my $resp = $packet->create_response( '603','Decline' );
                $endpoint->new_response( undef,$resp,$leg,$from );
		$log->info("blocked, ".$caller);

	    } else {

	        my $sth = $dbh->prepare("SELECT * from people where phone like ? limit 1");
	        $sth->execute("%".$caller."%");

		my $row = 0;
		while (my $h = $sth->fetchrow_arrayref) {
	    	    $log->info("incomming ".$h->[1]."->".$h->[2]);
		    if ($tv) {
			$log->info("notify tv for ".$h->[1]."->".$h->[2]);
			system("nfa notify -a $tv -n test -d 10s -m \"".($h->[2])."\" -t \"Τηλέφωνο από ".$h->[1]." \" > /dev/null");
		    }
		    $row++;
		}
	
		unless ($row) {
	    	    $log->info("incomming ".$caller);
		    if ($tv) {
	    		$log->info("notify tv for ".$caller);
			system("nfa notify -a 192.168.2.184 -n test -d 10s -m \"".($caller)."\" -t \"Τηλέφωνο\" > /dev/null") unless $sth->rows;
		    }
		}
	    }
	} else {
	    $log->debug("ignore ".$packet->dump);
	}
    };
$ua->{endpoint}->set_application( $receive );
$log->debug("App registered.");

# Register agent
$log->debug("Init registrar.");
my $register;
my $register_attempts=0;
my $register_count=0;
$register = sub {
    $log->debug("Register started.");
    $register_count++;
    my $expire = $ua->register;
    if ($ua->error){
	$log->error( "Failed to register:".$ua->error.", attempts=".$register_attempts.".");
	$register_attempts++;
	if ($register_attempts > 5) {
	    $log->warn( "Too many failed attempts(5), retry in 600 sec.");
	    $ua->add_timer(600, $register);
	    $register_attempts = 0;
	} else {
	    $log->warn( "Retry in 120 sec.");
	    $ua->add_timer(120, $register);
	}
    } else {
        $log->debug("Register got expire ".$expire." secs. Adding timer. Register counter=".$register_count.", attempts=".$register_attempts);
	$ua->add_timer($expire-10, $register);
    }

};

while ($continue) {
    $log->debug("Loop start...");
    $register->();
    $log->debug("Registrar complete...Looping...");
    $ua->loop;

    $log->info("End.");
}