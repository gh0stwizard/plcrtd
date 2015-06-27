# plcrtd #

plcrtd - Perl Certificates Daemon, an HTTP application OpenSSL CA manager 
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
* IO::FDPass
* Proc::FastSpawn

# Usage #

The program is splitted in three major parts:

* starter: <code>main.pl</code>
* backend: <code>backend/feersum.pl</code>
* application: <code>app/feersum.pl</code>

To start the program type in console:

```
shell> PERL5LIB=src/modules perl src/main.pl
```

The <code>PERL5LIB</code> environment variable is required and 
says Perl where is the additional modules are placed. So, 
you have not to copy (install) modules by a hand to start 
a program.

By default the server is listening on the address <code>127.0.0.1:28980</code>.
To run the listener on all interfaces and addresses you have to run
the server as described below:

```
shell> PERL5LIB=src/modules perl src/main.pl --listen 0.0.0.0:28980
```

# Options #

Use the option **--help** to see all available options:

```
shell> perl src/main.pl --help

TBA

```


# Usage with nginx #

The server is able to work together with [nginx](http://nginx.org).
The sample configuration file for nginx is placed in 
<code>conf/nginx/plcrtd.conf</code>.

Using plwrd together with nginx is a good idea, because nginx is intended 
to cache static files.

# API #

## Introduction ##

A server side works together with a frontend side via AJaX requests.
Requests are splitted into two groups: GET and POST. The GET requests
are using mostly to retrieving a data from the server. Meantime the
POST requests are using to storing a data on the server.

All types of requests are using JSON encoding.

## How to catch an error ##

When an error occurs on the server side, the server will response with
a hash object. In that case _all_ types of requests returns 
the hash object with only one key <code>err</code>.
The value for the key is a number with an error code.

Currently, the server is using next error codes:

* <code>0</code> - Connection error
* <code>1</code> - Bad request
* <code>2</code> - Not implemented
* <code>3</code> - Internal error


## GET requests ##

Currently, all GET requests are using the next semantic:

```
?action=ACTION&name=NAME
```

where is ACTION means a command to execute on the server,
and NAME is additional argument. Some actions runs without
the NAME parameter.

A list of actions and their descriptions:

TBA

## POST requests ##

The POST requests are working like the GET requests. They are
also using parameters ACTION and NAME like shows above. In an
addition POST requests may have other parameters, all of them
are described below.

A list of actions and their descriptions:

TBA
