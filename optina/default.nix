{ secrets }:
{ lib, config, pkgs, ... }:

{
  imports =
    [
      ./hardware.nix
    ];
  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  profiles.vim.enable = true;
  profiles.zsh.enable = true;
  profiles.tmux.enable = true;
  profiles.passopolis.enable = true;

  networking = {
    hostName = "optina.wedlake.lan";
    interfaces.enp2s0.ip4 = [ { address = "10.40.33.20"; prefixLength = 24; } ];
    defaultGateway = "10.40.33.1";
    nameservers = [ "10.40.33.20" "8.8.8.8" ];
    extraHosts =
    ''
      10.233.1.2 rtorrent.optina.local
    '';
    nat = {
      enable = true;
      internalInterfaces = ["ve-+"];
      externalInterface = "enp2s0";
    };
    firewall = {
      enable = true;
      allowPing = true;
      allowedTCPPorts = [ 443 32400 445 139 53 24000 3000 6667 6600 8080 22022 8000 8083 8086 9100 9093 9090 4444 5900 8091 9100 ];
      allowedUDPPorts = [ 53 137 138 1194 500 4500 ];
    };
  };

  security.pki.certificates = [ secrets.wedlake_ca_cert ];

  nixpkgs.config = {
    allowUnfree = true;
  };
  environment.systemPackages = with pkgs; [
    unrar
    unzip
    zip
    gnupg
    gnupg1compat
    weechat
    rxvt_unicode
    tcpdump
    nix-prefetch-git
    ncmpc
    git
    fasd
  ];

  services = {
    openssh = {
      enable = true;
      permitRootLogin = "without-password";
      passwordAuthentication = false;
    };
    unifi.enable = true;
    #telegraf = {
    #  enable = true;
    #  extraConfig = {
    #    outputs = {
    #      influxdb = [{
    #        urls = ["http://localhost:8086"];
    #        database = "telegraf";
    #      }];
    #      prometheus_client = [{
    #        listen = ":9101";
    #      }];
    #    };
    #    inputs = {
    #      cpu = [{}];
    #      disk = [{}];
    #      diskio = [{}];
    #      kernel = [{}];
    #      mem = [{}];
    #      swap = [{}];
    #      netstat = [{}];
    #      nstat = [{}];
    #      ntpq = [{}];
    #      procstat = [{}];
    #    };
    #  };
    #};
    prometheus = {
      enable = true;
      extraFlags = [
        "-storage.local.retention 8760h"
        "-storage.local.series-file-shrink-ratio 0.3"
        "-storage.local.memory-chunks 2097152"
        "-storage.local.max-chunks-to-persist 1048576"
        "-storage.local.index-cache-size.fingerprint-to-metric 2097152"
        "-storage.local.index-cache-size.fingerprint-to-timerange 1048576"
        "-storage.local.index-cache-size.label-name-to-label-values 2097152"
        "-storage.local.index-cache-size.label-pair-to-fingerprints 41943040"
      ];
      blackboxExporter = {
        enable = true;
        configFile = pkgs.writeText "blackbox-exporter.yaml" (builtins.toJSON {
        modules = {
          https_2xx = {
            prober = "http";
            timeout = "5s";
            http = {
              fail_if_not_ssl = true;
            };
          };
          ssh_banner = {
            prober = "tcp";
            timeout = "10s";
            tcp = {
              query_response = [ { expect = "^SSH-2.0-"; } ];
            };
          };
          tcp_v4 = {
            prober = "tcp";
            timeout = "5s";
            tcp = {
              preferred_ip_protocol = "ip4";
            };
          };
          tcp_v6 = {
            prober = "tcp";
            timeout = "5s";
            tcp = {
              preferred_ip_protocol = "ip6";
            };
          };
          icmp_v4 = {
            prober = "icmp";
            timeout = "5s";
            icmp = {
              preferred_ip_protocol = "ip4";
            };
          };
          icmp_v6 = {
            prober = "icmp";
            timeout = "5s";
            icmp = {
              preferred_ip_protocol = "ip6";
            };
          };
        };
      });
      };
      surfboardExporter = {
        enable = true;
      };
      nodeExporter = {
        enable = true;
        enabledCollectors = [
          "systemd"
          "tcpstat"
          "conntrack"
          "diskstats"
          "entropy"
          "filefd"
          "filesystem"
          "loadavg"
          "meminfo"
          "netdev"
          "netstat"
          "stat"
          "time"
          "vmstat"
          "systemd"
          "logind"
          "interrupts"
          "ksmd"
        ];
      };
      unifiExporter = {
        enable = true;
        unifiAddress = "https://unifi.wedlake.lan";
        unifiUsername = "prometheus";
        unifiPassword = secrets.unifi_password_ro;
        openFirewall = true;
      };
      alertmanagerURL = [ "http://localhost:9093" ];
      rules = [
        ''
          ALERT node_down
          IF up == 0
          FOR 5m
          LABELS {
            severity="page"
          }
          ANNOTATIONS {
            summary = "{{$labels.alias}}: Node is down.",
            description = "{{$labels.alias}} has been down for more than 5 minutes."
          }
          ALERT node_systemd_service_failed
          IF node_systemd_unit_state{state="failed"} == 1
          FOR 4m
          LABELS {
            severity="page"
          }
          ANNOTATIONS {
            summary = "{{$labels.alias}}: Service {{$labels.name}} failed to start.",
            description = "{{$labels.alias}} failed to (re)start service {{$labels.name}}."
          }
          ALERT node_filesystem_full_90percent
          IF sort(node_filesystem_free{device!="ramfs"} < node_filesystem_size{device!="ramfs"} * 0.1) / 1024^3
          FOR 5m
          LABELS {
            severity="page"
          }
          ANNOTATIONS {
            summary = "{{$labels.alias}}: Filesystem is running out of space soon.",
            description = "{{$labels.alias}} device {{$labels.device}} on {{$labels.mountpoint}} got less than 10% space left on its filesystem."
          }
          ALERT node_filesystem_full_in_4h
          IF predict_linear(node_filesystem_free{device!="ramfs"}[1h], 4*3600) <= 0
          FOR 5m
          LABELS {
            severity="page"
          }
          ANNOTATIONS {
            summary = "{{$labels.alias}}: Filesystem is running out of space in 4 hours.",
            description = "{{$labels.alias}} device {{$labels.device}} on {{$labels.mountpoint}} is running out of space of in approx. 4 hours"
          }
          ALERT node_filedescriptors_full_in_3h
          IF predict_linear(node_filefd_allocated[1h], 3*3600) >= node_filefd_maximum
          FOR 20m
          LABELS {
            severity="page"
          }
          ANNOTATIONS {
            summary = "{{$labels.alias}} is running out of available file descriptors in 3 hours.",
            description = "{{$labels.alias}} is running out of available file descriptors in approx. 3 hours"
          }
          ALERT node_load1_90percent
          IF node_load1 / on(alias) count(node_cpu{mode="system"}) by (alias) >= 0.9
          FOR 1h
          LABELS {
            severity="page"
          }
          ANNOTATIONS {
            summary = "{{$labels.alias}}: Running on high load.",
            description = "{{$labels.alias}} is running with > 90% total load for at least 1h."
          }
          ALERT node_cpu_util_90percent
          IF 100 - (avg by (alias) (irate(node_cpu{mode="idle"}[5m])) * 100) >= 90
          FOR 1h
          LABELS {
            severity="page"
          }
          ANNOTATIONS {
            summary = "{{$labels.alias}}: High CPU utilization.",
            description = "{{$labels.alias}} has total CPU utilization over 90% for at least 1h."
          }
          ALERT node_ram_using_90percent
          IF node_memory_MemFree + node_memory_Buffers + node_memory_Cached < node_memory_MemTotal * 0.1
          FOR 30m
          LABELS {
            severity="page"
          }
          ANNOTATIONS {
            summary="{{$labels.alias}}: Using lots of RAM.",
            description="{{$labels.alias}} is using at least 90% of its RAM for at least 30 minutes now.",
          }
          ALERT node_swap_using_80percent
          IF node_memory_SwapTotal - (node_memory_SwapFree + node_memory_SwapCached) > node_memory_SwapTotal * 0.8
          FOR 10m
          LABELS {
            severity="page"
          }
          ANNOTATIONS {
            summary="{{$labels.alias}}: Running out of swap soon.",
            description="{{$labels.alias}} is using 80% of its swap space for at least 10 minutes now."
          }
        ''
      ];
      scrapeConfigs = [
        {
          job_name = "prometheus";
          scrape_interval = "5s";
          static_configs = [
            {
              targets = [
                "localhost:9090"
              ];
            }
          ];
        }
        {
          job_name = "telegraf";
          scrape_interval = "10s";
          static_configs = [
            {
              targets = [
                "localhost:9101"
              ];
              labels = {
                alias = "crate.wedlake.lan";
              };
            }
          ];
        }
        {
          job_name = "node";
          scrape_interval = "10s";
          static_configs = [
            {
              targets = [
                "portal.wedlake.lan:9100"
              ];
              labels = {
                alias = "portal.wedlake.lan";
              };
            }
            {
              targets = [
                "optina.wedlake.lan:9100"
              ];
              labels = {
                alias = "optina.wedlake.lan";
              };
            }
            {
              targets = [
                "prod01.wedlake.lan:9100"
              ];
              labels = {
                alias = "prod01.wedlake.lan";
              };
            }
          ];
        }
        {
          job_name = "surfboard";
          scrape_interval = "5s";
          static_configs = [
            {
              targets = [
                "localhost:9239"
              ];
            }
          ];
        }
        {
          job_name = "unifi";
          scrape_interval = "10s";
          static_configs = [
            {
              targets = [
                "localhost:9130"
              ];
              labels = {
                alias = "unifi.wedlake.lan";
              };
            }
          ];
        }
        {
          job_name = "blackbox";
          scrape_interval = "60s";
          metrics_path = "/probe";
          params = {
            module = [ "ssh_banner" ];
          };
          static_configs = [
            {
              targets = [
                "73.230.94.119"
              ];
            }
          ];
          relabel_configs = [
            {
              source_labels = [ "__address__" ];
              regex = "(.*)(:.*)?";
              replacement = "\${1}:22";
              target_label = "__param_target";
            }
            {
              source_labels = [ "__param_target" ];
              target_label = "instance";
            }
            {
              source_labels = [];
              target_label = "__address__";
              replacement = "127.0.0.1:9115";
            }
          ];
        }
      ];
      alertmanager = {
        enable = true;
        listenAddress = "0.0.0.0";
        configuration = {
          "global" = {
            "smtp_smarthost" = "smtp.gmail.com:587";
            "smtp_from" = "alertmanager@samleathers.com";
            "auth_identity" = "disasm@gmail.com";
            "auth_password" = secrets.alertmanager_smtp_pw;
          };
          "pushover" = {
            "user_key" = secrets.alertmanager_pushover_user;
            "token" = secrets.alertmanager_pushover_token;
          };
          "route" = {
            "group_by" = [ "alertname" "alias" ];
            "group_wait" = "30s";
            "group_interval" = "2m";
            "repeat_interval" = "4h";
            "receiver" = "team-admins";
          };
          "receivers" = [
            {
              "name" = "team-admins";
              "email_configs" = [
                {
                  "to" = "disasm@gmail.com";
                  "send_resolved" = true;
                }
              ];
              "webhook_configs" = [
                {
                  "url" = "https://crate.wedlake.lan/prometheus-alerts";
                  "send_resolved" = true;
                }
              ];
            }
          ];
        };
      };
    };
    grafana = {
      enable = true;
      addr = "0.0.0.0";
    };
    ympd = {
      enable = true;
      webPort = "8082";
      mpd.host = "10.40.33.20";
    };
    phpfpm = {
      phpPackage = pkgs.php71;
      poolConfigs = {
        mypool = ''
          listen = 127.0.0.1:9000
          user = nginx
          pm = dynamic
          pm.max_children = 5
          pm.start_servers = 1
          pm.min_spare_servers = 1
          pm.max_spare_servers = 2
          pm.max_requests = 50
          env[NEXTCLOUD_CONFIG_DIR] = "/var/nextcloud/config"
        '';
      };
      phpOptions =
      ''
      [opcache]
      opcache.enable=1
      opcache.memory_consumption=128
      opcache.interned_strings_buffer=8
      opcache.max_accelerated_files=4000
      opcache.revalidate_freq=60
      opcache.fast_shutdown=1
      '';
        };
        nginx = {
        enable = true;
        httpConfig = ''
        error_log /var/log/nginx/error.log;
        server {
          listen [::]:443 ssl;
          listen *:443 ssl;
          server_name  crate.wedlake.lan;

          ssl_certificate      /data/ssl/nginx.crt;
          ssl_certificate_key  /data/ssl/nginx.key;

          ssl_session_cache    shared:SSL:1m;
          ssl_session_timeout  5m;

          ssl_ciphers  HIGH:!aNULL:!MD5;
          ssl_prefer_server_ciphers  on;

          location / {
            proxy_pass http://localhost:8089/;
          }
        }
        server {
          listen [::]:443 ssl;
          listen *:443 ssl;
          server_name  unifi.wedlake.lan;

          ssl_certificate      /data/ssl/unifi.wedlake.lan.crt;
          ssl_certificate_key  /data/ssl/unifi.wedlake.lan.key;

          ssl_session_cache    shared:SSL:1m;
          ssl_session_timeout  5m;

          ssl_ciphers  HIGH:!aNULL:!MD5;
          ssl_prefer_server_ciphers  on;

          location / {
            proxy_set_header Referer "";
            proxy_pass https://localhost:8443/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forward-For $proxy_add_x_forwarded_for;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
          }
        }
        server {
          listen [::]:443 ssl;
          listen *:443 ssl;
          server_name  mpd.wedlake.lan;

          ssl_certificate      /data/ssl/mpd.wedlake.lan.crt;
          ssl_certificate_key  /data/ssl/mpd.wedlake.lan.key;

          ssl_session_cache    shared:SSL:1m;
          ssl_session_timeout  5m;

          ssl_ciphers  HIGH:!aNULL:!MD5;
          ssl_prefer_server_ciphers  on;

          location / {
            proxy_pass http://127.0.0.1:8082;
            # Websocket
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade"; 
          }
        }
        '';
      };

      samba = {
        enable = true;
        shares = {
          meganbackup =
          { path = "/data/backups/other/megan";
          "valid users" = "sam megan";
          writable = "yes";
          comment = "Megan's Backup";
          };
          musicdrive =
          { path = "/data/pvr/music";
          "valid users" = "sam megan nursery";
          writable = "yes";
          comment = "music share";
          };
          };
          extraConfig = ''
          guest account = nobody
          map to guest = bad user
          '';
          };
          printing = {
          enable = true;
          drivers = [ pkgs.hplip ];
          defaultShared = true;
          browsing = true;

          };
          openvpn = {
          servers = {
          wedlake = {
          config = ''
          dev tun
          proto udp
          port 1194
          tun-ipv6
          ca /data/openvpn/ca.crt
          cert /data/openvpn/crate.wedlake.lan.crt
          key /data/openvpn/crate.wedlake.lan.key
          dh /data/openvpn/dh2048.pem
          server 10.40.12.0 255.255.255.0
          server-ipv6 2601:98a:4101:d352::/64
          push "route 10.40.33.0 255.255.255.0"
          push "route-ipv6 2601:98a:4101:d350::/60"
          push "route-ipv6 2000::/3"
          push "dhcp-option DNS 10.40.33.20"
          duplicate-cn
          keepalive 10 120
          tls-auth /data/openvpn/ta.key 0
          comp-lzo
          user openvpn
          group root
          persist-key
          persist-tun
          status openvpn-status.log
          verb 3
          '';
          };
          };
          };

        icecast = {
          enable = true;
          hostname = "prophet.samleathers.com";
          admin.password = secrets.mpd_admin_pw;
          extraConf = ''
            <mount type="normal">
            <mount-name>/mpd.ogg</mount-name>
            <username>mpd</username>
            <password>${secrets.mpd_user_pw}</password>
            </mount>
          '';
        };
        mpd = {
          enable = false;
          musicDirectory = "/data/pvr/music";
          extraConfig = ''
            log_level "verbose"
            restore_paused "no"
            metadata_to_use "artist,album,title,track,name,genre,date,composer,performer,disc,comment"
            bind_to_address "10.40.33.20"
            password "mpd@${secrets.mpd_admin_pw},read,add,control"

            input {
            plugin "curl"
            }
            audio_output {
            type        "shout"
            encoding    "ogg"
            name        "Icecast stream"
            host        "prophet.samleathers.com"
            port        "8000"
            mount       "/mpd.ogg"
            public      "yes"
            bitrate     "192"
            format      "44100:16:1"
            user        "mpd"
            password    "${secrets.mpd_user_pw}"
            }
            audio_output {
            type "alsa"
            name "fake out"
            driver "null"
            }
          '';
        };
        powerdns = {
          enable = true;
          extraConfig = ''
            launch=gpgsql
            allow-recursion=10.0.0.0/8
            recursor=127.0.0.1:8699
            local-address=10.40.33.20
            gpgsql-host=127.0.0.1
            gpgsql-dbname=pdns
            gpgsql-user=pdns
            gpgsql-password=${secrets.powerdns_pg_pw}
            api=yes
            api-key=${secrets.powerdns_api_key}
            webserver=yes
          '';
        };
        pdns-recursor = {
          enable = true;
          dns.allowFrom = [ "127.0.0.1/8" ];
          dns.port = 8699;
          extraConfig = ''
            forward-zones-recurse=.=8.8.8.8;7.7.7.7
          '';
        };

        postgresql = {
          enable = true;
          # Only way to get passopolis to work
          # Lock this down once we migrate away from passopolis
          authentication = ''
            local all all trust
            host  all all 127.0.0.1/32 trust
          '';
        };
        postgresqlBackup.enable = true;

      };
      virtualisation.docker.enable = true;
      virtualisation.docker.enableOnBoot = true;
      virtualisation.docker.storageDriver = "btrfs";
      containers.rtorrent = {
        privateNetwork = true;
        hostAddress = "10.233.1.1";
        localAddress = "10.233.1.2";
        enableTun = true;
        config = { config, pkgs, ... }: {
          environment.systemPackages = with pkgs; [
            rtorrent
            openvpn
            tmux
            sudo
          ];
          users.extraUsers.rtorrent = {
            isNormalUser = true;
            uid = 10001;
          };
        };
      };
      users.extraUsers.sam = {
        isNormalUser = true;
        description = "Sam Leathers";
        uid = 1000;
        extraGroups = [ "wheel" ];
        openssh.authorizedKeys.keys = secrets.sam_ssh_keys;
      };
      users.extraUsers.mitro = {
        isNormalUser = true;
        uid = 1001;
      };
      users.extraUsers.megan = {
        isNormalUser = true;
        uid = 1002;
      };
      users.extraUsers.openvpn = {
        isNormalUser = true;
        uid = 1003;
      };
      users.extraUsers.nursery = {
        isNormalUser = true;
        uid = 1004;
      };
  # don't change this without reading release notes
  system.stateVersion = "17.09";
}