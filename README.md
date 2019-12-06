This project contains several ZoneMinder control modules that I created for my cameras.

- Wansview Q1 Camera - https://www.wansview.com/cn/proinfo.aspx?proid=4&aids=1

The "*.pm" files are Perl modules that should be installed in the /usr/share/perl5/vendor_perl/ZoneMinder/Control/ directory.

The "*.sql" files are used with the zmcamtool.pl utility to register the camera module in ZoneMinder:

    $ sudo zmcamtool.pl --import modulename.sql

The telnet2WansviewQ1 script is a hack that lets you telnet into the camera for exploration purposes.  It has no real value but it was a byproduct of my attempts to understand this camera.
