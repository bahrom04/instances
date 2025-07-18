{
  lib,
  domains,
  pkgs,
}: let
  commonHeaders = ''
    add_header Permissions-Policy interest-cohort=() always;
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
    add_header X-XSS-Protection "1; mode=block";
  '';

  matrixHeaders = ''
    ${commonHeaders}

    # Should match synapse homeserver setting max_upload_size
    client_max_body_size 50M;
    # The maximum body size for client requests to any of the endpoints on the Client-Server API.
    # This needs to be equal or higher than the maximum upload size accepted by Synapse.
    client_body_buffer_size 50M;
    proxy_max_temp_file_size 0;
  '';

  clientConfig = import ./client.nix {inherit domains;};

  wellKnownClient = domain: {
    "m.homeserver".base_url = "https://${domains.server}";
    "m.identity_server".base_url = "https://${domains.server}";
    "org.matrix.msc2965.authentication" = {
      issuer = "https://${domains.auth}/";
      account = "https://${domains.auth}/account";
    };
    "im.vector.riot.e2ee".default = true;
    "io.element.e2ee" = {
      default = true;
      secure_backup_required = false;
      secure_backup_setup_methods = [];
    };
    "org.matrix.msc4143.rtc_foci" = [
      {
        "type" = "livekit";
        "livekit_service_url" = "https://livekit-jwt.call.matrix.org";
      }
    ];
  };

  wellKnownServer = domain: {"m.server" = "${domains.server}:443";};

  wellKnownSupport = {
    contacts = [
      {
        email_address = "support@${domains.main}";
        matrix_id = "@orzklv:${domains.main}";
        role = "m.role.admin";
      }
    ];
    support_page = "https://${domains.main}/about";
  };

  mkWellKnown = data: ''
    add_header Content-Type application/json;
    add_header Access-Control-Allow-Origin *;
    return 200 '${builtins.toJSON data}';
  '';

  wellKnownLocations = domain: {
    "= /.well-known/matrix/server".extraConfig = mkWellKnown (wellKnownServer domain);
    "= /.well-known/matrix/client".extraConfig = mkWellKnown (wellKnownClient domain);
    "= /.well-known/matrix/support".extraConfig = mkWellKnown wellKnownSupport;
  };

  wellKnownAppleLocations = domain: {
    "= /.well-known/apple-app-site-association". extraConfig = let
      data = {
        applinks = {
          apps = [
            "86VMSY4FK5.uz.uzinfocom.efael.app"
            "7J4U792NQT.io.element.elementx"
          ];
          details = [];
        };
        webcredentials = {
          apps = [
            "86VMSY4FK5.uz.uzinfocom.efael.app"
            "7J4U792NQT.io.element.elementx"
          ];
        };
      };
    in ''
      default_type application/json;
      types { application/json apple-app-site-association; }
      return 200 '${builtins.toJSON data}';
    '';
  };

  mkLocation = type: endpoint: {
    "~* ${endpoint}" = {
      extraConfig = ''
        ${commonHeaders}
        add_header x-backend "worker-${type}" always;
      '';
      proxyPass = "http://matrix-${type}-receiver";
      priority = 175;
    };
  };

  mkEndpoints = type: file: let
    rawEndpoints = lib.splitString "\n" (builtins.readFile file);
    filteredEndpoints = builtins.filter (e: e != "" && (!lib.hasPrefix "#" e)) rawEndpoints;
    mkLocation' = mkLocation type;
  in
    builtins.map mkLocation' filteredEndpoints;

  endpoints =
    (mkEndpoints "client" ./endpoints/client.txt)
    ++ (mkEndpoints "federation" ./endpoints/federation.txt);
in {
  services.www.hosts = {
    ${domains.main} = {
      locations =
        {}
        // wellKnownLocations "${domains.main}"
        // wellKnownAppleLocations "${domains.main}";
    };

    ${domains.client} = {
      forceSSL = true;
      enableACME = true;
      root = pkgs.element-web.override {conf = clientConfig;};
      extraConfig = commonHeaders;
    };

    ${domains.auth} = {
      root = "/dev/null";

      forceSSL = lib.mkDefault true;
      enableACME = lib.mkDefault true;

      extraConfig = commonHeaders;

      locations =
        {
          "/" = {
            proxyPass = "http://127.0.0.1:8080";
          };
        }
        // wellKnownAppleLocations "${domains.main}";
    };

    ${domains.server} = {
      root = "/dev/null";

      forceSSL = lib.mkDefault true;
      enableACME = lib.mkDefault true;

      locations =
        (lib.foldl' lib.recursiveUpdate {} (
          [
            {
              # Forward to the auth service
              "~ ^/_matrix/client/(.*)/(login|logout|refresh)" = {
                priority = 100;
                proxyPass = "http://127.0.0.1:8080";
                extraConfig = commonHeaders;
              };

              # Forward to Synapse
              # as per https://element-hq.github.io/synapse/latest/reverse_proxy.html#nginx
              "~ ^(/_matrix|/_synapse)" = {
                priority = 200;
                proxyPass = "http://127.0.0.1:8008";

                extraConfig = ''
                  ${matrixHeaders}
                  add_header x-backend "synapse" always;
                '';
              };
            }
          ]
          # ++ endpoints
        ))
        // wellKnownAppleLocations "${domains.main}";
    };
  };

  networking.firewall.allowedTCPPorts = [8448];
}
