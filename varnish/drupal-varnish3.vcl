# Sample VCL based on VCL created by Four Kitchens, available at
# https://fourkitchens.atlassian.net/wiki/display/TECH/Configure+Varnish+3+for+Drupal+7
/*
 * Copyright (c) 2013 Four Kitchens
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL AUTHOR OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
 * BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 * OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
 * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

# Default backend definition.  Set this to point to your content server.
backend default {
  .host = "127.0.0.1";
  .port = "81";
}

sub vcl_recv {
  # Use anonymous, cached pages if all backends are down.
  if (!req.backend.healthy) {
    unset req.http.Cookie;
  }

  # Allow the backend to serve up stale content if it is responding slowly.
  set req.grace = 6h;

  # Do not cache these paths.
  if (req.url ~ "^/status\.php$" ||
      req.url ~ "^/update\.php$" ||
      req.url ~ "^/admin$" ||
      req.url ~ "^/admin/.*$" ||
      req.url ~ "^/flag/.*$" ||
      req.url ~ "^.*/ajax/.*$" ||
      req.url ~ "^.*/ahah/.*$") {
       return (pass);
  }

  # Always cache the following file types for all users. This list of extensions
  # appears twice, once here and again in vcl_fetch, so make sure you edit both
  # and keep them equal.
  if (req.url ~
    "(?i)\.(pdf|txt|doc|xls|ppt|csv|png|gif|jpeg|jpg|ico|swf|css|js)(\?.*)?$") {
    unset req.http.Cookie;
  }

  # Remove all cookies that Drupal doesn't need to know about. We explicitly
  # list the ones that Drupal does need, the SESS and NO_CACHE cookies. If after
  # running this code we find that either of these two cookies remains, we
  # will pass as the page shouldn't be cached.
  if (req.http.Cookie) {
    # Append a semicolon to the front of the cookie string.
    set req.http.Cookie = ";" + req.http.Cookie;

    # Remove all spaces that appear after semicolons.
    set req.http.Cookie = regsuball(req.http.Cookie, "; +", ";");

    # Match the cookies we want to keep, adding back the space we removed
    # previously. "\1" is first matching group in the regular expression match.
    set req.http.Cookie = regsuball(req.http.Cookie,
                          ";(SESS[a-z0-9]+|SSESS[a-z0-9]+|NO_CACHE)=", "; \1=");

    # Remove all other cookies, identifying them by the fact that they have
    # no space after the preceding semicolon.
    set req.http.Cookie = regsuball(req.http.Cookie, ";[^ ][^;]*", "");

    # Remove all spaces and semicolons from the beginning and end of the
    # cookie string.
    set req.http.Cookie = regsuball(req.http.Cookie, "^[; ]+|[; ]+$", "");

    if (req.http.Cookie == "") {
      # If there are no remaining cookies, remove the cookie header
      # so that Varnish will cache the request.
      unset req.http.Cookie;
    }
    else {
      # If there are any cookies left (a session or NO_CACHE cookie), do not
      # cache the page. Pass it on to the backend directly.
      return (pass);
    }
  }
}

sub vcl_deliver {
  # Set a header to track if this was a cache hit or miss.
  # Include hit count for cache hits.
  if (obj.hits > 0) {
    set resp.http.X-Varnish-Cache = "HIT";
    set resp.http.X-Varnish-Hits = obj.hits;
  }
  else {
    set resp.http.X-Varnish-Cache = "MISS";
  }
}

sub vcl_fetch {
  # Items returned with these status values wouldn't be cached by default,
  # but by doing so we can save some Drupal overhead.
  if (beresp.status == 404 || beresp.status == 301 || beresp.status == 500) {
    set beresp.ttl = 10m;
  }

  # Don't allow static files to set cookies.
  # This list of extensions appears twice, once here and again in vcl_recv, so
  # make sure you edit both and keep them equal.
  if (req.url ~
    "(?i)\.(pdf|txt|doc|xls|ppt|csv|png|gif|jpeg|jpg|ico|swf|css|js)(\?.*)?$") {
    unset beresp.http.set-cookie;
  }

  # Allow items to be stale if needed, in case of problems with the backend.
  set beresp.grace = 6h;
}

sub vcl_error {
  # In the event of an error, show friendlier messages.
  set obj.http.Content-Type = "text/html; charset=utf-8";
  synthetic {"
<html>
<head>
  <title>Page Unavailable</title>
  <style>
    body { background: #303030; text-align: center; color: white; }
    .error { color: #222; }
  </style>
</head>
<body>
  <div id="page">
    <h1 class="title">Page Unavailable</h1>
    <p>The page you requested is temporarily unavailable.</p>
    <p>Please try again later.</p>
    <div class="error">(Error "} + obj.status + " " + obj.response + {")</div>
  </div>
</body>
</html>
"};
  return (deliver);
}
