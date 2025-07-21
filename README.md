# home framework
<i>Bring home to the production!</i>

## Features
+ TLS only
+ HTTP1.1
+ Single-threaded / Multi-threaded (Isolates)

## Additional information
There should be done optimization with TLS handshake and overall.
Without TLS I got about 18k RPS (single connection - single response, no reuse), with TLS less than 200 RPS, when Go server without TLS got 130k. 
Probably the good news is that Pyhton without TLS got worse in my tests. Heh.