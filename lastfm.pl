# lastfm.pl -- last.fm now playing script for irssi
# Patroklos Argyroudis, argp at domain sysc.tl

use strict;
use vars qw($VERSION %IRSSI);
use Irssi qw(command_bind active_win);
use LWP::UserAgent;
use utf8;

$VERSION = '0.3';

%IRSSI =
(
    authors     => 'Patroklos Argyroudis',
    contact     => 'argp at domain sysc.tl',
    name        => 'last.fm now playing',
    description => 'polls last.fm and displays the most recent audioscrobbled track',
    license     => 'BSD',
    url         => 'https://github.com/argp/lastfm-irssi',
    changed     => 'Fri Aug 29 16:46:47 IST 2008',
    commands    => 'lastfm np',
);

my $timeout_seconds = 120;
my $timeout_flag;
my $np_username = '';
my $username;
my $cached;
my $proxy_str = '';
my @channels;

sub show_help()
{
    my $help = "lastfm $VERSION
/lastfm start <username>
    start a last.fm now playing session
/lastfm stop
    stop the active last.fm now playing session
/lastfm timeout <seconds>
    specify the polling timeout in seconds (default: 120),
    be careful when changing the default value, too
    aggressive polling may get your IP blacklisted
/lastfm channel <command> [channel name]
    manipulate display channels, command can be add, del or list
/lastfm proxy <hostname> <port>
    set an HTTP proxy (default: none)
/np [username (only required on the first invocation)]
    display the most recent audioscrobbled track in the active window";

    my $text = '';
    
    foreach(split(/\n/, $help))
    {
        $_ =~ s/^\/(.*)$/%9\/$1%9/;
        $text .= $_."\n";
    }
    
    Irssi::print("$text");
}

sub cmd_lastfm
{
    my ($argv, $server, $dest) = @_;
    my @arg = split(/ /, $argv);
    
    if($arg[0] eq '')
    {
        show_help();
    }
    elsif($arg[0] eq 'timeout')
    {
        if($arg[1] eq '')
        {
            show_help();
        }
        else
        {
            $timeout_seconds = $arg[1];
        }
    }
    elsif($arg[0] eq 'proxy')
    {
        if($arg[1] eq '' || $arg[2] eq '')
        {
            show_help();
        }
        else
        {
            $proxy_str = "$arg[1]:$arg[2]";
            Irssi::print("last.fm HTTP proxy set to http://$proxy_str");
        }
    }
    elsif($arg[0] eq 'channel')
    {
        if($arg[1] eq '')
        {
            show_help();
        }
        elsif($arg[1] eq 'list')
        {
            if(defined($channels[0]))
            {
                Irssi::print("last.fm display channels: @channels");
            }
            else
            {
                Irssi::print('last.fm display channels: none specified');
            }
        }
        elsif($arg[1] eq 'add')
        {
            if($arg[2] eq '')
            {
                show_help();
            }
            else
            {
                push(@channels, $arg[2]);
                Irssi::print("channel $arg[2] added to last.fm display channels");
            }
        }
        elsif($arg[1] eq 'del')
        {
            if($arg[2] eq '')
            {
                show_help();
            }
            else
            {
                my @new_channels = grep(!/$arg[2]/, @channels);
                @channels = ();
                @channels = @new_channels;
                @new_channels = ();
                Irssi::print("channel $arg[2] deleted from the last.fm display channels");
            }
        }
    }
    elsif($arg[0] eq 'help')
    {
        show_help();
    }
    elsif($arg[0] eq 'stop')
    {
        if(defined($timeout_flag))
        {
            Irssi::timeout_remove($timeout_flag);
            $timeout_flag = undef;
            Irssi::print("last.fm now playing session ($username) stopped");
        }
    }
    elsif($arg[0] eq 'start')
    {
        if($arg[1] eq '')
        {
            show_help();
        }
        else
        {
            if(defined($timeout_flag))
            {
                Irssi::timeout_remove($timeout_flag);
                $timeout_flag = undef;
                Irssi::print("previous last.fm now playing session ($username) stopped");
            }
            
            $username = $arg[1];
            
            if($timeout_seconds)
            {
                $timeout_flag = Irssi::timeout_add(($timeout_seconds * 1000), 'lastfm_poll', '');
            }
            
            Irssi::print("last.fm now playing session ($username) started");
            
            if(defined($channels[0]))
            {       
                Irssi::print("last.fm display channels: @channels");
            }   
            else
            {       
                Irssi::print('last.fm only displaying in the active window');
            }
        }
    }
}

sub lastfm_get
{
    my $uname = shift;
    my $lfm_url = "http://ws.audioscrobbler.com/1.0/user/$uname/recenttracks.txt";
    my $agent = LWP::UserAgent->new();
    $agent->agent('argp\'s last.fm irssi script');

    if($proxy_str ne '')
    {
        $agent->proxy(['http', 'ftp'] => "http://$proxy_str");
    }

    $agent->timeout(60);
    
    my $request = HTTP::Request->new(GET => $lfm_url);
    my $result = $agent->request($request);

    $result->is_success or return;

    my $str = $result->content;
    my @arr = split(/\n/, $str);
    my $new_track = '';
    $new_track = $arr[0];
    $new_track =~ s/^[0-9]*,//;
    $new_track =~ s/\xe2\x80\x93/-/;

    # I like my announcements in lowercase
    $new_track =~ tr/A-Z/a-z/;

    return $new_track;
}

sub cmd_np
{
    my ($argv, $server, $dest) = @_;
    my @arg = split(/ /, $argv);
    my $np_track = '';

    if($arg[0] eq '' and $np_username eq '')
    {
        show_help();
        return;
    }
    elsif($np_username eq '' and $arg[0] ne '')
    {
        $np_username = $arg[0];
    }

    $np_track = lastfm_get($np_username);
    active_win->command("/me np: $np_track");
}

sub lastfm_poll
{
    my $new_track = '';

    $new_track = lastfm_get($username);

    if($cached eq $new_track)
    {
        return;
    }
    else
    {
        if(defined($channels[0]))
        {
            foreach my $chan_name (@channels)
            {
                foreach my $chan (Irssi::channels())
                {
                    if($chan_name eq $chan->{'name'})
                    {
                        $chan->window->command("/me np: $new_track");
                    }
                }
            }
        }
        else
        {
            active_win->command("/me np: $new_track");
        }
  
        $cached = $new_track;
    }
}

Irssi::command_bind('lastfm', 'cmd_lastfm');
Irssi::command_bind('np', 'cmd_np');
Irssi::print("last.fm now playing script v$VERSION, /lastfm help for help");

# EOF
