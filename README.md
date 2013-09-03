ampr
====

Automatic Multi Path Route

1. License and acceptable use
2. Theory of operation
3. Configuration file format
4. Examples
5. Troubleshooting

----------------------------------------------------------------------------------------------------

1. Licence and acceptable use
=============================

Copyright (C) 2013 Diego Augusto Molina

This program is free software; you can redistribute it and/or modify it under the terms of the GNU
General Public Licence Version 2 as published by the Free Software Foundation.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public Licence for more details.

You should have recieved a copy of the GNU General Public Licence along with this program; if not,
write to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307,
USA.

2. Theory of operation
======================

The program relies on specific routes for hosts to determine the availability of a path. If INIT is
non zero, the program will make these routes for you. Basically what it will do is to create a
unicast route that matches a single host usning a specific nexthop router. Then, it will use the
'pingmon' function to ping that host. That ICMP request will be sent to the remote host through the
nexthop router due to the route we had created previously. The 'pingmon' function will then tell the
main program when the connection to the remote host is 'acceptable', which will cause the main
program to add the nexthop router to the multipath route. The 'pingmon' function may consider the
connection 'acceptable, but with high latency', in which case the nexthop router is weighted
accordingly in the multipath route to favour other paths. When the 'pingmon' function determines
there is no connection available the path will be brought down, without affecting the other paths,
and flushing all the routes that were cached through that nextop router. When no path is available,
the entire route is deleted.

3. Configuration file format
============================

The file is a regular INI file. The special section [general] serves to declare default values.
Comments start with a hash sign (#) and occupy the rest of the line. White space is trimmed from
lines and comments are removed when parsing.

The following are the values that can be declared in the [general] section:
*   NWEIGHT: default weight for normal paths.
*   HLWEIGHT: weight for high latency paths.
*   INIT: wether to initialize the special routes for each remote host behind the nexthop routers
    (see later). Set to non zero to enable.
*   PINGMONOPTS: default options to pass to 'pingmon' function, which is the function that performs
    monitoring.
*   REST: sleep for this number of seconds after completion of each group of operations. This value
    will be passed to 'sleep'.
*   PRETEND: if non zero, will run the whole program but will write to stdout the 'ip' commands
    instead of actually executing them.
*   TROUBLESHOOT: if non zero, will run interactively and ask where to save a troubleshooting report
    to attach to a bug report.
You can declare the [general] section as many times you want: each variable declaration overwrites
the previous one.
Any other section will be interpreted as a multipath route definition, and each line of the contents
of that section a path definition of that multipath route. The header itself serves as the starting
arguments to 'ip route replace' or 'ip route delete'. So you may specify any arguments you want for
the route in that header, like 'table mytab', 'metric 2'. The only one that cannot be missing is
the 'to' argument (for obvious reasons). Examples:
    [default]
    [192.168.2.0/24 scope global src 192.168.1.1 metric 10]

The rest of the arguments to the 'ip' command, namely the nexthops, will be added dynamically when
they are determined to be available. Each nexthop definition is a white space separated list of
items in the same line. Each line is supposed to have at least three items. The items will be
interpreted in the following order:
1.  IP address of the remote host to monitor through this path.
2.  Network interface name.
3.  Nexthop router.
4.  Normal weight and small weight (for high latencies) for this specific path, separated by a
    comma. If only one value is given it will be interpreted as the normal weight.
5.  The rest of the items will be passed 'as-is' to the 'pingmon' function, so that you can make any
    particular configuration for a path.
Examples:
    8.8.8.8 eth0 10.0.0.2
    4.4.4.4 eth1 10.0.0.3 1,2

*IMPORTANT NOTE*: no validation is done on the arguments passed to the 'ip' command. Correctness
relies entirely on your veification.

4. Examples
===========

See the "ampr.ini" file for a comprehensive configuraion example.

5. Troubleshooting
==================

Remember that you should first run the program with the "PRETEND=1" option set in your configuration
file in order to see what would actually be done. The program comes with some safe defaults, but
your particular combination of network connectivity and network state may require some tweaking, so
make sure you are also satisfied with the options passed to pingmon. You can use "ampr pìngmon
[options] remote-host" to see what the main program sees, and that might help you to understand why
it is behaving "strange". One of the symptoms of this "strangeness" may be that paths are detected
as having high latency too soon, or unexpectedly go down. A good choice of remote hosts helps a lot.
You can start by using hosts in the local network to make the first tests.

Send all bug reports to diegoaugustomolina@gmail.com with a subject begginning with "[ampr]" and
attach the troubleshooting report file generated by ampr when provided "TROUBLESHOOT=1" in the
configuration file. The bug report should contain any output of the program that you think is
valuable, a description of the working environment, like how connectivity is set, and any other
"relevant" information. Feel free to change the actual addresses, networks, names, etc. in order to
preserve your privacy. I'm personally not interested in that boring information, but you may want to
save it from other viewers. But REMEMBER to mask the actual characters of the play in such a fashion
that the actual scenario can be reproduced. Otherwise you may not get the help you need.  If you do
care about your organization's privacy, remember to review and edit the troubleshooting file report
before sending it. The most important thing it has is the configuration file you provided ampr.

