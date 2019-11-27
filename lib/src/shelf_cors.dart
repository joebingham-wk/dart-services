// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library shelf_cors;

import 'package:shelf/shelf.dart';

// TODO: Rename to createCorsHeadersMiddleware or corsHeadersMiddleware?

/// Middleware which adds [CORS headers](https://developer.mozilla.org/en-US/docs/Web/HTTP/Access_control_CORS)
/// to shelf responses. Also handles preflight (OPTIONS) requests.
Middleware createCorsHeadersMiddleware({Map<String, String> corsHeaders = const {}}) {
  return (Handler innerHandler) {
    return (request) {
      final origin = request.headers['origin'];

      final headers = {
        ...corsHeaders,
        // We can't use `*` or we'll get this CORS error:
        //     The value of the 'Access-Control-Allow-Origin' header in the response must not be the wildcard '*' when the request's credentials mode is 'include'.
        //     The credentials mode of requests initiated by the XMLHttpRequest is controlled by the withCredentials attribute.
        'Access-Control-Allow-Origin': origin,
        'Access-Control-Allow-Credentials': 'true',
      };

      return Future.sync(() {
        // Handle preflight (OPTIONS) requests by just adding headers and an empty
        // response.
        if (request.method == 'OPTIONS') {
          return Response.ok(null, headers: headers);
        } else {
          return null;
        }
      }).then((response) {
        if (response != null) return response;

        return Future.sync(() => innerHandler(request)).then((response) {
          return response.change(headers: headers);
        });
      });
    };
  };
}
