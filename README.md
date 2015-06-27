# plcrtd #

plcrtd - Perl OpenSSL Certificate Manager Daemon, an HTTP application
written in [Perl](http://www.perl.org).

# Why? #

Just for fun. The possible usecases:

* Personal usage
* Internal usage inside a company

# Dependencies #

This software requires next modules and libraries installed
via CPAN or other Perl package management system:

* EV
* AnyEvent
* Feersum
* HTTP::Body
* HTML::Entities
* JSON::XS
* File::Spec
* Getopt::Long
* Sys::Syslog (optional)

# Usage #

The program is splitted in three major parts:

* starter: <code>main.pl</code>
* backend: <code>backend/feersum.pl</code>
* application: <code>app/feersum.pl</code>

To start the program type in console:

```
shell> perl src/main.pl
```

By default the server is listening on the address <code>127.0.0.1:28980</code>.
To run the listener on all interfaces and addresses you have to run
the server as described below:

```
shell> perl src/main.pl --listen 0.0.0.0:28980
```

# Options #

Use the option **--help** to see all available options:

```
shell> perl src/main.pl --help
Allowed options:
  --help [-h]              prints this information
  --version                prints program version

Web server options:
  --listen [-l] arg        IP:PORT for listener
                           - default: "127.0.0.1:28980"
  --background [-B]        run process in background (disables logging)
                           - default: runs in foreground
Security options:
  --home [-H] arg          working directory after fork
                           - default: root directory
Logging options:
  --debug                  be verbose
  --verbose                be very verbose
  --quiet [-q]             disables logging totally
  --enable-syslog          enable logging via syslog
  --syslog-facility arg    syslog's facility (default is LOG_DAEMON)
  --logfile [-L] arg       path to log file (default is stdout)

Miscellaneous options:
  --pidfile [-P] arg       path to pid file (default: none)
  --backend [-b] arg       backend name (default: feersum)
  --app [-a] arg           application name (default: feersum)
```

# Usage with nginx #

The server was created to working together with [nginx](http://nginx.org).
The sample configuration file for nginx is placed in 
<code>conf/nginx/plcrtd.conf</code>.

# Security #

You have to install HTTPS server, e.g. nginx, and set up it as a frontend
for this application. Because of the Feersum module, 
the embeded HTTP server, does not working with HTTPS.

Due the limitation above you are unable to use **plcrtd** without
HTTP(S) frontend server, sorry.

# API #

## Introduction ##

A server side works together with a client side via AJaX requests.
Currently the server side accepts only POST requests.

All types of requests are using JSON encoding.

## How to catch an error ##

When an error occurs on the server side, the server will response with
a hash object. In that case _all_ types of requests returns
the hash object with key <code>err</code> always.
The value for the key is a number with an error code.

Some types of requests also produces <code>msg</code> key
with error description.

Currently, the server is using next error codes:

* <code>0</code> - Connection error
* <code>1</code> - Bad request
* <code>2</code> - Not implemented
* <code>3</code> - Internal error

## POST requests ##

A list of actions and their descriptions:

* genCAkey
* genCAcrt

### genCAkey ###

Generates key. The method accepts next arguments:

* <code>action</code> = genCAkey
* <code>pass</code> - password for a key
* <code>bits</code> - number of bits

Returns a hash object with key <code>key</code>.

### genCAcrt ###

Generates CA certificate. The method accepts next arguments:

* <code>action</code> = genCAcrt
* <code>key</code> - pre-generated key
* <code>pass</code> - password for the key
* <code>days</code> - a number of days
* <code>subj</code> - subject, e.g. '/C=US/ST=Texas/O=gh0stwizard/CN=plcrtd'

