# ==========================================================================
#
# ZoneMinder WansviewQ1 Control Protocol Module, Date: 2019-08-19, Revision: 0001
# Copyright (C) 2019 David King <dave@daveking.com>
# Modified DBPower.pm for use with Wansview Q1 Camera - Dave King
#   - Rename module to ZoneMinder::Control::WansviewQ1
#   - Add "status=1" parameter to setPreset URI
#   - Camera does not support a "Home" preset, modify presetHome URI to use preset #1
#     as the "Home" preset
#   - Removed Zoom and Focus functions that this camera does not support
# Modified for use with DBPower IP Camera by Oliver Welter
#   Rename to DBPower
#   Added Zoom, Focus, hPatrol, vPatrol
#   Implemented digest authentication
# Modified for use with Foscam FI8918W IP Camera by Dave Harris
# Modified Feb 2011 by Howard Durdle (http://durdl.es/x) to:
#      fix horizontal panning, add presets and IR on/off
#      use Control Device field to pass username and password
# Modified June 5th, 2012 by Chris Bagwell to:
#   Rename to IPCAM since its common protocol with wide range of cameras.
#   Work with Logger module instead of Debug module.
#   Fix off-by-1 preset bug.
#   Support optional autostop timeout.
#   Add Zoom, Brightness, and Contrast support.
# Modified July 7th, 2012 by Patrik Brander to:
#   Rename to Wanscam
#   Pan Left/Right switched
#   IR On/Off switched
#   Brightness Increase/Decrease in 16 steps
# Modified Dec 20, 2017 by Dave King to:
#   Rename back to IPCAM since it is a common protocol used by multiple vendors
#
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
#
# ==========================================================================
#
# This module contains the implementation of the IPCAM camera control
# protocol.
#
# This is a protocol shared by a wide range of affordable cameras that
# appear to share similar reference design and software.  Examples
# include Foscam, Agasio, Wansview, etc.
#
# The basis for CGI based API can be found on internet by searching for
# "IPCAM CGI SDK 2.1". Here is sample site that also developes replacement
# firmware for some hardware versions.
#
# http://www.openipcam.com/files/Manuals/IPCAM%20CGI%20SDK%202.1.pdf
#
package ZoneMinder::Control::WansviewQ1;

use 5.006;
use strict;
use warnings;

require ZoneMinder::Base;
require ZoneMinder::Control;

our @ISA = qw(ZoneMinder::Control);

use ZoneMinder::Logger qw(:all);
use ZoneMinder::Config qw(:all);

use Time::HiRes qw( usleep );

use LWP::UserAgent;
use URI;

sub new
{
    my $class = shift;
    my $id = shift;
    my $self = ZoneMinder::Control->new( $id );
    my $logindetails = "";
    bless( $self, $class );
    srand( time() );
    return $self;
}

our $AUTOLOAD;

sub AUTOLOAD
{
    my $self = shift;
    my $class = ref($self) || croak( "$self not object" );
    my $name = $AUTOLOAD;
    $name =~ s/.*://;
    if ( exists($self->{$name}) )
    {
        return( $self->{$name} );
    }
    Fatal( "Can't access $name member of object of class $class" );
}

sub open
{
    my $self = shift;

    $self->loadMonitor();

    use LWP::UserAgent;
    $self->{ua} = LWP::UserAgent->new;
    $self->{ua}->agent( "ZoneMinder Control Agent/".ZoneMinder::Base::ZM_VERSION );

    $self->{state} = 'open';
}

sub close
{
    my $self = shift;
    $self->{state} = 'closed';
}

sub printMsg
{
    my $self = shift;
    my $msg = shift;
    my $msg_len = length($msg);

    Debug( $msg."[".$msg_len."]" );
}

sub sendDigestCmd
{
    my $self = shift;
    my $cmd = shift;
    my $result = undef;

    my $url = new URI("http://".$self->{Monitor}->{ControlAddress}."/$cmd");
    my $ua = LWP::UserAgent->new('ZoneMinder');

    my $realm = "IPCamera Login";
    my $uri = $url->scheme."://".$url->host.":".$url->port.$url->path."?".$url->query;

    my @userinfo = split(":", $url->userinfo());
    my $username = $userinfo[0];
    my $password = $userinfo[1];

    if ($username && $password)
    {
      $ua->credentials($url->host.":".$url->port, $realm, $username => $password);
      printMsg( $cmd, "Login with user ".$username );
    }

    my $res = $ua->get($uri);
    printMsg( $cmd, "Tx" );

    if ( $res->is_success )
    {
        $result = $res->decoded_content;
    }
    else
    {
        Error( "Error check failed:'".$res->status_line()."'" );
    }

    return( $result );
}

sub reset
{
    my $self = shift;
    Debug( "Camera Reset" );
    my $cmd = "hy-cgi/device.cgi?cmd=sysreboot";
    $self->sendDigestCmd( $cmd );
}

sub stop
{
    my $self = shift;
    Debug( "Stop" );
    my $cmd = "hy-cgi/ptz.cgi?cmd=ptzctrl&act=stop";
    $self->sendDigestCmd( $cmd );
}

sub moveConUp
{
    my $self = shift;
    my $params = shift;
    Debug( "Move Up" );
    my $speed = $self->getParam( $params, 'tiltspeed', 0x01 );
    my $cmd = "hy-cgi/ptz.cgi?cmd=ptzctrl&act=up&speed=$speed";
    $self->sendDigestCmd( $cmd );
    my $autostop = $self->getParam( $params, 'autostop', 0 );
    if ( $autostop && $self->{Monitor}->{AutoStopTimeout} )
    {
        usleep( $self->{Monitor}->{AutoStopTimeout} );
        $self->stop( $params );
    }
}

sub moveConDown
{
    my $self = shift;
    my $params = shift;
    Debug( "Move Down" );
    my $speed = $self->getParam( $params, 'tiltspeed', 0x01 );
    my $cmd = "hy-cgi/ptz.cgi?cmd=ptzctrl&act=down&speed=$speed";
    $self->sendDigestCmd( $cmd );
    my $autostop = $self->getParam( $params, 'autostop', 0 );
    if ( $autostop && $self->{Monitor}->{AutoStopTimeout} )
    {
        usleep( $self->{Monitor}->{AutoStopTimeout} );
        $self->stop( $params );
    }
}

sub moveConRight
{
    my $self = shift;
    my $params = shift;
    Debug( "Move Right" );
    my $speed = $self->getParam( $params, 'panspeed', 0x01 );
    my $cmd = "hy-cgi/ptz.cgi?cmd=ptzctrl&act=right&speed=$speed";
    $self->sendDigestCmd( $cmd );
    my $autostop = $self->getParam( $params, 'autostop', 0 );
    if ( $autostop && $self->{Monitor}->{AutoStopTimeout} )
    {
        usleep( $self->{Monitor}->{AutoStopTimeout} );
        $self->stop( $params );
    }
}

sub moveConLeft
{
    my $self = shift;
    my $params = shift;
    Debug( "Move Left" );
    my $speed = $self->getParam( $params, 'panspeed', 0x01 );
    my $cmd = "hy-cgi/ptz.cgi?cmd=ptzctrl&act=left&speed=$speed";
    $self->sendDigestCmd( $cmd );
    my $autostop = $self->getParam( $params, 'autostop', 0 );
    if ( $autostop && $self->{Monitor}->{AutoStopTimeout} )
    {
        usleep( $self->{Monitor}->{AutoStopTimeout} );
        $self->stop( $params );
    }
}

sub horizontalPatrol
{
    my $self = shift;
    my $params = shift;
    Debug( "Horizontal Partrol" );
    my $speed = $self->getParam( $params, 'panspeed', 0x01 );
    my $cmd = "hy-cgi/ptz.cgi?cmd=ptzctrl&act=hscan&speed=$speed";
    $self->sendDigestCmd( $cmd );
}

sub horizontalPatrolStop
{
    my $self = shift;
    my $params = shift;
    $self->stop( $params );
}

sub verticalPatrol
{
    my $self = shift;
    my $params = shift;
    Debug( "Vertical Partrol" );
    my $speed = $self->getParam( $params, 'tiltspeed', 0x01 );
    my $cmd = "hy-cgi/ptz.cgi?cmd=ptzctrl&act=vscan&speed=$speed";
    $self->sendDigestCmd( $cmd );
}

sub verticalPatrolStop
{
    my $self = shift;
    my $params = shift;
    $self->stop( $params );
}

sub presetHome
{
    my $self = shift;
    Debug( "Home Preset" );
    my $cmd = "hy-cgi/ptz.cgi?cmd=preset&act=goto&number=1";
    $self->sendDigestCmd( $cmd );
}

sub presetSet
{
    my $self = shift;
    my $params = shift;
    my $preset = $self->getParam( $params, 'preset' );
    Debug( "Set Preset $preset" );
    my $cmd = "hy-cgi/ptz.cgi?cmd=preset&act=set&status=1&number=$preset";
    $self->sendDigestCmd( $cmd );
}

sub presetGoto
{
    my $self = shift;
    my $params = shift;
    my $preset = $self->getParam( $params, 'preset' );
    Debug( "Goto Preset $preset" );
    my $cmd = "hy-cgi/ptz.cgi?cmd=preset&act=goto&number=$preset";
    $self->sendDigestCmd( $cmd );
}
1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 Wansview Q1 Camera Control Module for ZoneMinder

=head1 SYNOPSIS

ZoneMinder::Control::WansviewQ1 - Zoneminder Camera Control Module

Derived from ZoneMinder::Control::DBPower module by Oliver Welter
https://forums.zoneminder.com/viewtopic.php?t=23792

=head1 AUTHOR

Dave King <dave@daveking.com>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2019  Dave King

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=cut
