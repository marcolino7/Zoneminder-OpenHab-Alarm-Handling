# Zoneminder-OpenHab-Alarm-Handling
This script is designed to get Alarm state from Zoneminder and send to OpenHab.
OpenHab have some Switch Items set to ON when a camera go into Alert or Alarm State

It's a perl script based on this script from Zoneminder:

https://github.com/ZoneMinder/ZoneMinder/blob/master/utils/zm-alarm.pl

I got monitor handling part from this script:

https://github.com/pliablepixels/zmeventserver/blob/master/zmeventnotification.pl

#Run as daemon
You can run this Perl script as daemon, using http://www.libslack.org/daemon/

Inside project you can find a script to place into /etc/init.d
