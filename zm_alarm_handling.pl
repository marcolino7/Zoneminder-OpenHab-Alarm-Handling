#!/usr/bin/perl -w

#use LWP::UserAgent;
use strict;

use ZoneMinder;
use warnings;
use DBI;

$| = 1;

$SIG{INT}  = \&signal_handler;
$SIG{TERM} = \&signal_handler;

use constant OPENHAB_URL => "http://openhab2:8080";
use constant MONITOR_RELOAD_INTERVAL => 300;
use constant SLEEP_DELAY=>2;

my %monitors;
my $dbh = zmDbConnect();
my $monitor_reload_time = 0;
my $apns_feedback_time = 0;
my $proxy_reach_time=0;
my $wss;
my @events=();
my @active_connections=();
my $alarm_header="";
my $alarm_mid="";
my $alarmEventId = 1;           # tags the event id along with the alarm - useful for correlation
my @camstatus = ("NONE","NONE","NONE","NONE","NONE","NONE","OFF","OFF","OFF","OFF","OFF","OFF"); #Array che contiene gli stati delle camere
my @firstrun = (0,0,0,0,0,0,0,0,0,0,0,0);
my @alarmcount = (0,0,0,0,0,0,0,0,0,0,0,0);

Info( "Alarm Monitor Handling module starting" );

while( 1 )
{

	my $eventFound = 0;
    if ( (time() - $monitor_reload_time) > MONITOR_RELOAD_INTERVAL )
        {
        Info ("Reloading Monitors...\n");
        foreach my $monitor (values(%monitors))
        {
            zmMemInvalidate( $monitor );
        }
        loadMonitors();
		Info ("Firstrun status= @firstrun\n");
		Info ("Alarm Status= @camstatus\n");
    }


    @events = ();
    $alarm_header = "";
    $alarm_mid="";
    foreach my $monitor ( values(%monitors) )
    {
        next if ( !zmMemVerify( $monitor ) );

		my ( $state, $last_event )
            = zmMemRead( $monitor,
                 [ "shared_data:state",
                   "shared_data:last_event"
                 ]
			);
		
		#Decodifica Stati
		#STATE_IDLE     => 0;
		#STATE_PREALARM => 1;
		#STATE_ALARM    => 2;
		#STATE_ALERT    => 3;
		#STATE_TAPE     => 4;
		
		#Info("Last Event=".$last_event." State=".$state);
        if ($state == STATE_ALARM || $state == STATE_ALERT)
        {
			Info ("Alarm Detected on cam=".$monitor->{Name});
			if (@camstatus[$monitor->{Id}] ne decodeState($state))
			{
				my $count = @alarmcount[$monitor->{Id}];
				$count = $count+1;
				#if ($count >= 2) {
					&sendtoOH($monitor->{Id},$state);
				#}
				@camstatus[$monitor->{Id}] = decodeState($state);
				@alarmcount[$monitor->{Id}] = $count;
				Info ("Alarm Count= @alarmcount\n");
			}
		}
		
		if ($state == STATE_IDLE || $state == STATE_TAPE)
        {
			Info ("Alarm Rearmed on cam=".$monitor->{Name});
			if (@camstatus[$monitor->{Id}] ne decodeState($state))
			{
				@alarmcount[$monitor->{Id}] = 0;
				
				&sendtoOH($monitor->{Id},$state);
				@camstatus[$monitor->{Id}] = decodeState($state);
				Info ("Alarm Count= @alarmcount\n");
			}
		}
    }
	#Info ("cam status= @camstatus\n");
    sleep( SLEEP_DELAY );
}

sub decodeState
{
	use Switch;
	my ($stato) = @_;
	my $oh_state = "NONE";
	
	switch ($stato) {
		case 2		{ $oh_state = "ON"; }
		case 3		{ $oh_state = "ON"; }
		case 4		{ $oh_state = "OFF"; }
		case 0		{ $oh_state = "OFF"; }
		else		{ $oh_state = "NONE"; }
	}
	return ($oh_state);
}

#Compone il comando e lo invia via http to OpenHab
sub sendtoOH
{

	my ($monid, $stato) = @_;
	my $oh_state = decodeState($stato);
	
	if ($oh_state ne "NONE")
	{
		#Gestisco il GET HTTP
		use REST::Client;
		my $host = OPENHAB_URL;
		my $client = REST::Client->new(host => $host);
		my $url = "/rest/items/CAM_ID".$monid."_ALARM/state";
		Info("Send Command to Server: ".OPENHAB_URL." with URL: ".$url." with command: ".$oh_state);
		#Write stuff;
		$client->PUT($url, $oh_state);
		Info("Client Result: ".$client);
	}
}

# Refreshes list of monitors from DB
# 
sub loadMonitors
{
    Info( "Loading monitors\n" );
    $monitor_reload_time = time();

    my %new_monitors = ();

    my $sql = "SELECT * FROM Monitors
               WHERE find_in_set( Function, 'Modect,Mocord,Nodect' )".
               ( $Config{ZM_SERVER_ID} ? 'AND ServerId=?' : '' );
    Debug ("SQL to be executed is :$sql");
     my $sth = $dbh->prepare_cached( $sql )
        or Fatal( "Can't prepare '$sql': ".$dbh->errstr() );
    my $res = $sth->execute( $Config{ZM_SERVER_ID} ? $Config{ZM_SERVER_ID} : () )
        or Fatal( "Can't execute: ".$sth->errstr() );
    while( my $monitor = $sth->fetchrow_hashref() )
    {
        next if ( !zmMemVerify( $monitor ) ); # Check shared memory ok

        if ( defined($monitors{$monitor->{Id}}->{LastState}) )
        {
            $monitor->{LastState} = $monitors{$monitor->{Id}}->{LastState};
        }
        else
        {
            $monitor->{LastState} = zmGetMonitorState( $monitor );
        }
        if ( defined($monitors{$monitor->{Id}}->{LastEvent}) )
        {
            $monitor->{LastEvent} = $monitors{$monitor->{Id}}->{LastEvent};
        }
        else
        {
            $monitor->{LastEvent} = zmGetLastEvent( $monitor );
        }
        $new_monitors{$monitor->{Id}} = $monitor;
		
		#Verifico se è il primo avvio resetto gli stati su OH
		if (@firstrun[$monitor->{Id}] == 0)
		{
			Info ("First Run - Sendig OFF to cam ID".$monitor->{Id});
			&sendtoOH($monitor->{Id},0);
			@firstrun[$monitor->{Id}] = 1;			
		}
    }
    %monitors = %new_monitors;
}

sub signal_handler {
	Info( "ZM Alarm Monitor Handling module stopping" );
	exit 0
}
