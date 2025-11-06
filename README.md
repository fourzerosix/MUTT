# 🍀 M.U.T.T. 🍀 ( Module Usage Tracking Tool )

## Summary
This document/project was planned/executed in accordance with the [Lmod Tracking Module Usage Doc](https://lmod.readthedocs.io/en/latest/300_tracking_module_usage.html).

Once you have a module system, it can be useful to know what modules your users are loading. We can use `syslog` to track module usage, collect this data into a database, then query that database for detailed module usage statistics. Module-load accounting requires supplying a `SitePackage.lua` with load-hooks (via `LMOD_PACKAGE_PATH`), configuring it to emit syslog-ready messages, collecting those via rsyslog and:
- Sending to our local Graylog instance for real-time detailed statistics, and/or
- Collecting into a database, and then running the supplied `analyzeLmodDB` scripts to generate statistics.

Starting in Lmod 8.7.54+, there is a complete “Gen2” tracking solution that we can leverageon our clusters via:
1. A Customized `SitePackage.lua` in an alternative location ( `/etc/lmod/SitePackage.lua` ) registers load and exit hooks that comprise a list of modules a user loaded, then emits one syslog message per load at shell-exit.  
2. `rsyslog.d` on each compute node forwards those tagged ( `logger -t` ) messages ( `ModuleUsage` ) to a central log host via `/etc/rsyslog.d/module-usage-forward.conf`
3. The centralized logging-host uses `/etc/rsyslog.d/module-usage-tracking.conf` to write the messages into `/var/log/module-usage.log`.
*Sample output*:
   ```
   Oct 23 13:39:55 host GoodLawd_ModuleUsage[1039369]: user=suepeter module=miniconda3/25.1.1-2-6fzuizg path=/path/to/spack/linux-rocky9-x86_64/Core/miniconda3/25.1.1-2-6fzuizg.lua host=host jobid=interactive time=1761248395.978473
   Oct 23 13:40:34 host GoodLawd_ModuleUsage[1039636]: user=johnsonshat module=infrastructure/1.0.0-python3.12.2 path=/path/to/conda/infrastructure/1.0.0-python3.12.2.lua host=host jobid=interactive time=1761248434.848468
   Oct 23 13:53:31 host GoodLawd_ModuleUsage[1041234]: user=gottschalkjk module=py-cachetools/5.2.0-k2kfdmp path=/path/to/spack/linux-rocky9-x86_64/Core/py-cachetools/5.2.0-k2kfdmp.lua host=host jobid=interactive time=1761249208.841783
   ```
5. A cron job runs `store_module_data` (from Lmod’s `contrib/tracking_module_usage/gen_2`) to push logs into a MySQL database.  
6. Finally, you run `analyzeLmodDB` to query “`counts`”, “`usernames`”, or “`modules_used_by`” over date ranges.  

>[!NOTE]
>TO-DO
>- Ansible playbook
>  - On each client node we need:
>   - `/etc/lmod/SitePackage.lua`   | Lmod hook for module logging
>    - `rsyslog` forward rule        | Send usage logs to logging server
>    - `LMOD_PACKAGE_PATH=/etc/lmod` | Tell Lmod where to find SitePackage.lua
>    - `rsyslog` `sitepath.sh`       | Propagate custom Site Path (avoid modules.sh mod)

---

## Contents
* [Summary](#Summary)
* [Contents](#Contents)
* [Prerequisites](#Prerequisites)
* [Procedure](#Procedure)
* [Conclusion](#Conclusion)
* [See Also](#See-Also)
* [Archives](#Archives)

---

## Prerequisites
- MySQL database (version 8.0+)
  - `python3-PyMySQL:0.10.1-6.el9.noarch`
  - `mysql          :8.0.41-2.el9_5`
  - `mysql-server   :8.0.41-2.el9_5`
- Rsyslog (version 8+)
- Lmod 8.7.54+
- `sudo` access
  
---

## Procedure

### STEP 1
Use `SitePackage.lua` to send a message to syslog  

1. `sudo mkdir -p /etc/lmod && sudo chown root:root /etc/lmod &&sudo chmod 0755 /etc/lmod`  
1. Edit the default [SitePackage.lua](https://github.here.there.com/suepeter/MUTT/blob/main/SitePackage.lua) and place it in `/etc/lmod`
1. Edit [`/etc/profile.d/modules.sh`](https://github.here.there.com/suepeter/MUTT/blob/main/modules.sh) to contain the line `export LMOD_PACKAGE_PATH=/etc/lmod`
1. In a new session/shell, check to see if the configuration is picked up by Lmod:
   ```bash
   [suepeter@host ~]$ module --config 2>&1 | grep -i sitepackage
   Site Pkg location                                             /etc/lmod/SitePackage.lua
   LMOD_SITEPACKAGE_LOCATION    Other      /usr/share/lmod/8.7.55/libexec/SitePackage.lua  /etc/lmod/SitePackage.lua
                lmod_cfg: lmod_config.lua SitePkg: SitePackage StdPkg: StandardPackage
   ```
1. Load a module and check to see if logs are being created:
   ```bash
   [suepeter@host ~]$ ml openmpi relion snpeff beast gcc
   [suepeter@host ~]$ sudo tail -10 /var/log/localmessages | grep ModuleUsage
   Nov  5 13:29:32 host ModuleUsage[52129]: user=suepeter module=zlib/1.3.1-ffl5dxu path=/path/to/spack/linux-rocky9-x86_64/Core/zlib/1.3.1-ffl5dxu.lua host=host jobid=interactive time=1762374572.273809
   Nov  5 13:29:32 host ModuleUsage[52130]: user=suepeter module=zstd/1.5.6-yucvkmw path=/path/to/spack/linux-rocky9-x86_64/Core/zstd/1.5.6-yucvkmw.lua host=host jobid=interactive time=1762374572.275249
   Nov  5 13:29:32 host ModuleUsage[52131]: user=suepeter module=beast path=/path/to/conda/beast.lua host=host jobid=interactive time=1762374572.205883
   Nov  5 13:29:32 host ModuleUsage[52132]: user=suepeter module=mpfr/4.2.1-sq6ffnk path=/path/to/spack/linux-rocky9-x86_64/Core/mpfr/4.2.1-sq6ffnk.lua host=host jobid=interactive time=1762374572.272400
   Nov  5 13:29:32 host ModuleUsage[52133]: user=suepeter module=gcc-runtime/11.3.1-pdjx7f4 path=/path/to/spack/linux-rocky9-x86_64/Core/gcc-runtime/11.3.1-pdjx7f4.lua host=host jobid=interactive time=1762374572.269768
   Nov  5 13:29:32 host ModuleUsage[52134]: user=suepeter module=gmp/6.3.0-q27rc3u path=/path/to/spack/linux-rocky9-x86_64/Core/gmp/6.3.0-q27rc3u.lua host=host jobid=interactive time=1762374572.270729
   Nov  5 13:29:32 host ModuleUsage[52135]: user=suepeter module=openmpi/5.0.8 path=/path/to/spack/linux-rocky9-x86_64/Core/openmpi/5.0.8.lua host=host jobid=interactive time=1762374572.181434
   Nov  5 13:29:32 host ModuleUsage[52136]: user=suepeter module=mpc/1.3.1-z6el743 path=/path/to/spack/linux-rocky9-x86_64/Core/mpc/1.3.1-z6el743.lua host=host jobid=interactive time=1762374572.272566
   Nov  5 13:29:32 host ModuleUsage[52137]: user=suepeter module=py-topaz/0.2.4 path=/path/to/spack/linux-rocky9-x86_64/openmpi/5.0.8-xnlxjsg/Core/py-topaz/0.2.4.lua host=host jobid=interactive time=1762374572.203087
   Nov  5 13:29:32 host ModuleUsage[52138]: user=suepeter module=relion/5.0.0 path=/path/to/spack/linux-rocky9-x86_64/openmpi/5.0.8-xnlxjsg/Core/relion/5.0.0.lua host=host jobid=interactive time=1762374572.203469
   ```

### STEP 2
Configure syslog
1. Edit `/etc/rsyslog.d/` on a test/client node by adding the [`module-usage-forward.conf`](https://github.here.there.com/suepeter/MUTT/blob/main/module-usage-forward.conf) configuration file and restarting `rsyslog`
   ```bash
   [suepeter@client ~]$ sudo vi /etc/rsyslog.d/module-usage-forward.conf

   # Forward module usage logs to central log server via UDP - suepeter - 2025-10-30
   if ($programname contains "ModuleUsage") then {
       action(
           type="omfwd"
           Target="host.here.there.com"
           Port="514"
           Protocol="udp"
           Template="RSYSLOG_TraditionalFileFormat"
       )
       stop
   }
   ```
   ```bash
   [suepeter@client ~]$ sudo systemctl restart rsyslog && sudo systemctl status rsyslog
   ● rsyslog.service - System Logging Service
        Loaded: loaded (/usr/lib/systemd/system/rsyslog.service; enabled; preset: enabled)
        Active: active (running) since Wed 2025-11-05 13:41:11 MST; 22ms ago
          Docs: man:rsyslogd(8)
                https://www.rsyslog.com/doc/
      Main PID: 1005046 (rsyslogd)
         Tasks: 3 (limit: 822093)
        Memory: 3.2M
           CPU: 59ms
        CGroup: /system.slice/rsyslog.service
                └─1005046 /usr/sbin/rsyslogd -n

   Nov 05 13:41:11 client.here.there.com systemd[1]: Starting System Logging Service...
   Nov 05 13:41:11 client.here.there.com rsyslogd[1005046]: [origin software="rsyslogd" swVersion="8.2310.0-4.el9" x-pid="1005046" x-info="https://www.rsyslog.com"] start
   Nov 05 13:41:11 client.here.there.com systemd[1]: Started System Logging Service.
   Nov 05 13:41:11 client.here.there.com rsyslogd[1005046]: imjournal: journal files changed, reloading...  [v8.2310.0-4.el9 try https://www.rsyslog.com/e/0 ]
   ```

### STEP 3
Setup the daemon **back on the central logging-host**
1. Edit `/etc/rsyslog.d/` by adding the [`module-usage-tracking.conf`](https://github.here.there.com/suepeter/MUTT/blob/main/module-usage-tracking.conf) configuration file and restarting `rsyslog`
   ```bash
   [suepeter@host ~]$ sudo vi /etc/rsyslog.d/module-usage-tracking.conf

   # Lmod Module Usage Tracking configuration
   # /etc/rsyslog.d/module-usage-tracking.conf
   # suepeter - 2025-11-04

   # Load UDP input module
   module(load="imudp")

   # Define ruleset to handle incoming Lmod tracking messages
   ruleset(name="remote") {
       if $programname contains 'ModuleUsage' then {
           action(type="omfile" FileCreateMode="0644" file="/var/log/module-usage.log")
           #action(type="omfile" file="/var/log/module-usage.log")
           stop
       }
   }

   # Bind UDP server to use that ruleset
   input(type="imudp" port="514" ruleset="remote")
   ```
   ```bash
   [suepeter@host ~]$ sudo systemctl restart rsyslog && sudo systemctl status rsyslog
   ● rsyslog.service - System Logging Service
        Loaded: loaded (/usr/lib/systemd/system/rsyslog.service; enabled; preset: enabled)
        Active: active (running) since Wed 2025-11-05 13:50:11 MST; 23ms ago
          Docs: man:rsyslogd(8)
                https://www.rsyslog.com/doc/
      Main PID: 53991 (rsyslogd)
         Tasks: 4 (limit: 822053)
        Memory: 4.2M
           CPU: 49ms
        CGroup: /system.slice/rsyslog.service
                └─53991 /usr/sbin/rsyslogd -n

   Nov 05 13:50:10 host.here.there.com systemd[1]: Starting System Logging Service...
   Nov 05 13:50:11 host.here.there.com rsyslogd[53991]: [origin software="rsyslogd" swVersion="8.2310.0-4.el9" x-pid="53991" x-info="https://www.rsyslog.com"] start
   Nov 05 13:50:11 host.here.there.com systemd[1]: Started System Logging Service.
   Nov 05 13:50:11 host.here.there.com rsyslogd[53991]: imjournal: journal files changed, reloading...  [v8.2310.0-4.el9 try https://www.rsyslog.com/e/0 ]
   
   [suepeter@host ~]$ ss -tulpn | grep 514
   udp   UNCONN 0      0            0.0.0.0:514       0.0.0.0:*
   udp   UNCONN 0      0               [::]:514          [::]:*
   ```
- *In any case, ur additions in `rsyslog.d` with this block from our `/etc/rsyslog.conf`*:
   ```
   # Include all config files in /etc/rsyslog.d/
   include(file="/etc/rsyslog.d/*.conf" mode="optional")
   ```

### STEP 4
1. Send a test via `logger` from a test/client node (`logger -t ModuleUsage` being taken directly from our `SitePackage.lua`)
   ```bash
   [suepeter@client ~]$ logger -t GoodLawdModuleUsageTracking "test from $(hostname)"
   13:53:30
   [suepeter@client ~]$ logger -t ModuleUsage "test from $(hostname)"
   13:53:41
   [suepeter@client ~]$ logger -t Module Usage "test from $(hostname)"
   13:54:13
   [suepeter@client ~]$ logger -t moduleusage "test from $(hostname)"
   13:54:25
   ```
- *As expected, only the first two logger messages were Kenny Loggins'd*
   ```bash
   [suepeter@host ~]$ sudo tail -2 /var/log/module-usage.log
   Nov  5 13:53:30 client GoodLawdModuleUsageTracking[1006264]: test from client.here.there.com
   Nov  5 13:53:41 client ModuleUsage[1006311]: test from client.here.there.com
   ```
1. Load some modules on the test/client and check the log files on the central log-host
   ##### *On the client*
   ```bash
   [suepeter@client ~]$ ml openmpi relion snpeff beast gcc
   ```
   ##### *On the centralized logging-host*
   ```bash
   [suepeter@host ~]$ sudo tail -17 /var/log/module-usage.log
   Nov  5 13:53:30 client GoodLawdModuleUsageTracking[1006264]: test from client.here.there.com
   Nov  5 13:53:41 client ModuleUsage[1006311]: test from client.here.there.com
   Nov  5 14:00:51 client ModuleUsage[1007052]: user=suepeter module=openjdk/17.0.8.1_1-usumfss path=/path/to/spack/linux-rocky9-x86_64/Core/openjdk/17.0.8.1_1-usumfss.lua host=client jobid=interactive time=1762376451.094294
   Nov  5 14:00:51 client ModuleUsage[1007053]: user=suepeter module=mpfr/4.2.1-sq6ffnk path=/path/to/spack/linux-rocky9-x86_64/Core/mpfr/4.2.1-sq6ffnk.lua host=client jobid=interactive time=1762376451.134658
   Nov  5 14:00:51 client ModuleUsage[1007054]: user=suepeter module=zlib/1.3.1-ffl5dxu path=/path/to/spack/linux-rocky9-x86_64/Core/zlib/1.3.1-ffl5dxu.lua host=client jobid=interactive time=1762376451.135937
   Nov  5 14:00:51 client ModuleUsage[1007055]: user=suepeter module=ctffind/4.1.14 path=/path/to/spack/linux-rocky9-x86_64/openmpi/5.0.8-xnlxjsg/Core/ctffind/4.1.14.lua host=client jobid=interactive time=1762376451.092174
   Nov  5 14:00:51 client ModuleUsage[1007056]: user=suepeter module=zstd/1.5.6-yucvkmw path=/path/to/spack/linux-rocky9-x86_64/Core/zstd/1.5.6-yucvkmw.lua host=client jobid=interactive time=1762376451.137247
   Nov  5 14:00:51 client ModuleUsage[1007057]: user=suepeter module=snpeff/2017-11-24-lnzhkx5 path=/path/to/spack/linux-rocky9-x86_64/Core/snpeff/2017-11-24-lnzhkx5.lua host=client jobid=interactive time=1762376451.094536
   Nov  5 14:00:51 client ModuleUsage[1007058]: user=suepeter module=gcc/13.2.0-tviiimi path=/path/to/spack/linux-rocky9-x86_64/Core/gcc/13.2.0-tviiimi.lua host=client jobid=interactive time=1762376451.137976
   Nov  5 14:00:51 client ModuleUsage[1007059]: user=suepeter module=relion/5.0.0 path=/path/to/spack/linux-rocky9-x86_64/openmpi/5.0.8-xnlxjsg/Core/relion/5.0.0.lua host=client jobid=interactive time=1762376451.093205
   Nov  5 14:00:51 client ModuleUsage[1007060]: user=suepeter module=beast path=/path/to/conda/beast.lua host=client jobid=interactive time=1762376451.095051
   Nov  5 14:00:51 client ModuleUsage[1007061]: user=suepeter module=gmp/6.3.0-q27rc3u path=/path/to/spack/linux-rocky9-x86_64/Core/gmp/6.3.0-q27rc3u.lua host=client jobid=interactive time=1762376451.133130
   Nov  5 14:00:51 client ModuleUsage[1007062]: user=suepeter module=gcc-runtime/11.3.1-pdjx7f4 path=/path/to/spack/linux-rocky9-x86_64/Core/gcc-runtime/11.3.1-pdjx7f4.lua host=client jobid=interactive time=1762376451.132300
   Nov  5 14:00:51 client ModuleUsage[1007063]: user=suepeter module=openmpi/5.0.8 path=/path/to/spack/linux-rocky9-x86_64/Core/openmpi/5.0.8.lua host=client jobid=interactive time=1762376451.073484
   Nov  5 14:00:51 client ModuleUsage[1007064]: user=suepeter module=glibc/2.34-kwsgimo path=/path/to/spack/linux-rocky9-x86_64/Core/glibc/2.34-kwsgimo.lua host=client jobid=interactive time=1762376451.132175
   Nov  5 14:00:51 client ModuleUsage[1007065]: user=suepeter module=py-topaz/0.2.4 path=/path/to/spack/linux-rocky9-x86_64/openmpi/5.0.8-xnlxjsg/Core/py-topaz/0.2.4.lua host=client jobid=interactive time=1762376451.092826
   Nov  5 14:00:51 client ModuleUsage[1007066]: user=suepeter module=mpc/1.3.1-z6el743 path=/path/to/spack/linux-rocky9-x86_64/Core/mpc/1.3.1-z6el743.lua host=client jobid=interactive time=1762376451.134825
   ```
   
### STEP 5
1. Setup the logrotate daemon in `/etc/logrotate.d` by adding the [`module-usage`](https://github.here.there.com/suepeter/MUTT/blob/main/module-usage) configuration file - *currently set to keep daily logs, rotated every 29 days*
   ```bash
   [suepeter@host ~]$ sudo vi /etc/logrotate.d/module-usage
   
   /var/log/module-usage.log {
      missingok
      copytruncate
      rotate 29
      daily
      create 644 root root
      notifempty
   }
   ```

### STEP 6
1. Install `python3-PyMySQL` via pip3 or your package manager.
> As of 2025-10-29, the most current version of this package is [`v1.1.2`](https://github.com/PyMySQL/PyMySQL) (2024),
>> but our package manager pulls `v0.10.1` (*which meets the prerequisite criteria for the Lmod tracking system as it supports Supports MySQL/MariaDB up to v8.0 <mark>and is compatible with our system python</mark> (**v3.9.21**)*.
>> *If your MySQL/MariaDB server uses standard mysql_native_password authentication, then PyMySQL 0.10.1 will work fine for Lmod’s usage logging — no issues at all.
>> It doesn’t use any advanced MySQL 8.0 features. However, if your MySQL instance uses the default caching_sha2_password authentication (as MySQL 8.0+ does by default), then PyMySQL 0.10.1 will fail to connect, because that auth method wasn’t supported until v1.0.0.*
   ```bash
   [root@host ~]# dnf install python3-PyMySQL
   ... lines omitted ...
   Installed:
   python3-PyMySQL-0.10.1-6.el9.noarch

   Complete!
   ```
1. Install relevant MySQL packages, w/o these you'll receive the error: `pymysql.err.OperationalError: (2003, "Can't connect to MySQL server on 'localhost' ([Errno 99] Cannot assign requested address)")`
   ```bash
   [root@host ~]# sudo dnf install mysql-server mysql
    Installing:
    mysql                    8.0.41-2.el9_5
    mysql-server             8.0.41-2.el9_5
    Installing dependencies:
    mecab                    0.996-3.el9.4
    mysql-common             8.0.41-2.el9_5
    mysql-errmsg             8.0.41-2.el9_5
    mysql-selinux            1.0.13-1.el9_5
    protobuf-lite            3.14.0-13.el9

   Complete!
   ```
1. Enable/Start `mysqld`
   ```bash
   [root@host ~]# sudo systemctl enable --now mysqld && sudo systemctl status mysqld
   Created symlink /etc/systemd/system/multi-user.target.wants/mysqld.service → /usr/lib/systemd/system/mysqld.service.

   ● mysqld.service - MySQL 8.0 database server
        Loaded: loaded (/usr/lib/systemd/system/mysqld.service; enabled; preset: disabled)
        Active: active (running) since Wed 2025-10-29 09:28:09 MDT; 6s ago
       Process: 1790681 ExecStartPre=/usr/libexec/mysql-check-socket (code=exited, status=0/SUCCESS)
       Process: 1790719 ExecStartPre=/usr/libexec/mysql-prepare-db-dir mysqld.service (code=exited, status=0/SUCCESS)
      Main PID: 1790804 (mysqld)
        Status: "Server is operational"
         Tasks: 38 (limit: 822053)
        Memory: 461.9M
           CPU: 1.798s
        CGroup: /system.slice/mysqld.service
                └─1790804 /usr/libexec/mysqld --basedir=/usr

   Oct 29 09:28:05 host.here.there.com systemd[1]: Starting MySQL 8.0 database server...
   Oct 29 09:28:05 host.here.there.com mysql-prepare-db-dir[1790719]: Initializing MySQL database
   Oct 29 09:28:09 host.here.there.com systemd[1]: Started MySQL 8.0 database server.
   ```
1. Create a MySQL user/account by logging in with `root` with a `[blank]`password. Then create the account in the database:
   ```bash
   [root@host ~]# mysql -u root -p
   Enter password:
   Welcome to the MySQL monitor.  Commands end with ; or \g.
   Your MySQL connection id is 9
   Server version: 8.0.41 Source distribution

   Copyright (c) 2000, 2025, Oracle and/or its affiliates.

   Oracle is a registered trademark of Oracle Corporation and/or its
   affiliates. Other names may be trademarks of their respective
   owners.

   Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.
   ```
1. Create your database structure (DBname/user/grants/etc.) (`GoodLawdlmod`,`DBUser`)
   ```sql
   mysql> CREATE DATABASE GoodLawdlmod;
   Query OK, 1 row affected (0.00 sec)

   mysql> CREATE USER 'DBUser'@'localhost' IDENTIFIED WITH mysql_native_password BY 'YourPasswordThatYouMustPutInPlainJaneTextForTheLoveOfYOUCANTSAYTHATWORDHERE';
   Query OK, 0 rows affected (0.01 sec)

   mysql> GRANT ALL ON GoodLawdlmod.* TO 'DBUser'@'localhost';
   Query OK, 0 rows affected (0.00 sec)

   mysql> flush privileges;
   Query OK, 0 rows affected (0.00 sec)

   mysql> quit;
   Bye
   ```
   <mark>***NIAID HPC specific inner-step***</mark>  
   | File                   | Purpose                                                             |
   |------------------------|---------------------------------------------------------------------|
   | **SitePackage.lua**    | Defines the hook that logs events via syslog.                       |
   | **store_module_data**  | Python script that parses syslog entries and stores them in the DB. |
   | **GoodLawdlmod_db.conf** | Database connection info (DB name, user, password, etc.).           |
   | **createDB.py**        | Initializes the MySQL schema.                                       |
   | **analyzeLmodDB**      | Reporting/query script (used in Step 9).                            |
   | **store.log**          | Log output from store_module_data script runs.                      |
1. You'll need scripts from [Lmod's gen_2 tracking module usage Githib page](https://github.com/TACC/Lmod/tree/main/contrib/tracking_module_usage/gen_2) for the next part - Create a new directory for the scripts and clone the Lmod repo, copy the scripts to your current working directory, and prune the unneeded portions of the download - leaving only the tools:
   ```bash
   [root@host ~]# mkdir -p /opt/lmod-tracking && cd /opt/lmod-tracking
   ```
   ```bash
   [root@host lmod-tracking]# git clone https://github.com/TACC/Lmod.git && mv Lmod/contrib/tracking_module_usage/gen_2/* . && rm -rf Lmod/
   ```
1. Replace the Lmod provided script with our own custom [`store_module_data`](https://github.here.there.com/suepeter/MUTT/blob/main/store_module_data) file
>[!NOTE]
>At this point, our log format is the standard syslog prefix followed by the `ModuleUsage[...]` tag and `key=value` pairs - which is the correct Lmod tracking format — but
>the `store_module_data parser` is choking in attempt to retrieve the host field from the wrong place. It expects a “`syshost`” string early in the log, but in our case the hostname is already present in the syslog prefix (*e.g., `client`*) and also provided as `host=client` at the end of the message. Due to testing w/the `logger` command, our log line doesn’t always contain a `host=` field, so when `dataT.get('host')` returns `None`, the function `syshost()` tries to do `None.split('.')`, which raises the `AttributeError`.
>I had to rewrite the supplied Lmod script to be more robust for our environment, as to
>>1. Handle missing host= gracefully (syshost() returns "unknown").  
>>2. Skip and logs lines with missing host or ignored modules.  
>>3. Print debug info if --debug is specified.  
>>4. Work safely with both JSON and standard log lines.  
>>5. Avoid .pyc cache issues.c  
1. Use the `conf_create` program from the `contrib/tracking_module_usage` directory to create a file containing the access information for the db:
   ```bash
   [root@host lmod-tracking]# ./conf_create
   Database host: localhost
   Database user: DBUser
   Database pass:
   Database name: GoodLawdlmod
   ```
>[!NOTE]
>*This creates a file named `GoodLawdlmod_db.conf` which is used by createDB.py, analyzeLmodDB and other programs to access the database.*
1. Create the database by running the `createDB.py` program
   ```bash
   [root@host lmod-tracking]# ./createDB.py
   Database host:localhost
   Database user:DBUser
   Database pass:
   Database name:GoodLawdlmod
   start
   (1) create moduleT table
   ```
### STEP 7-8
*If you have more than one cluster and you want to store them in the same database then make sure that your `load_hook` correctly sets the name of the cluster.*
We'll use a coupla 🤠 cron jobs to load/manage the `module-usage.log-*` files. We'll also use an in-house/AD-bound service account (`service_account`) to perform our various actions regarding 
   ```bash
   [root@host lmod-tracking]# touch /opt/lmod-tracking/delete.log
   [root@host lmod-tracking]# chown service_account:root /opt/lmod-tracking/delete.log && chmod 660 /opt/lmod-tracking/delete.log
   [root@host lmod-tracking]# chown -R service_account:root /opt/lmod-tracking/
   ```
   ```bash
   [root@host lmod-tracking]# cat /etc/cron.d/lmod-tracking
   # /etc/cron.d/lmod-tracking - suepeter - 2025-10-25
   # Run monthly on the 1st at 11:00 PM
   SHELL=/bin/bash
   PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/opt/lmod-tracking

   0 23 1 * * service_account /opt/lmod-tracking/delete_old_records --keepMonths 12 --yes --confFn /opt/lmod-tracking/GoodLawdlmod_db.conf > /opt/lmod-tracking/delete.log 2>&1
   ```
   ```bash
   [root@host lmod-tracking]# cat /etc/cron.d/lmod-tracking-store
   # /etc/cron.d/lmod-tracking-store - suepeter - 2025-10-29
   # Run daily at 4:44 AM to load module usage data
   SHELL=/bin/bash
   PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/opt/lmod-tracking

   44 4 * * * service_account /opt/lmod-tracking/store_module_data --delete --confFn /opt/lmod-tracking/GoodLawdlmod_db.conf /var/log/module-usage.log-* > /opt/lmod-tracking/store.log 2>&1
   ```
   ```bash
   [root@host lmod-tracking]# sudo -u service_account /opt/lmod-tracking/store_module_data --delete --confFn /opt/lmod-tracking/GoodLawdlmod_db.conf /var/log/module-usage.log-*
   [root@host lmod-tracking]# sudo -u service_account /opt/lmod-tracking/delete_old_records --keepMonths 12 --yes --confFn /opt/lmod-tracking/GoodLawdlmod_db.conf
   Deleting records with dates:    date < '2024-10-29'
   DELETE FROM moduleT where ( syshost LIKE %s )  and date < '2024-10-29'
   0 record(s) deleted
   ```

### STEP 9
Once data is being written to the database you can now start analyzing the data. **You can use SQL commands directly into the MySQL database** or you can use the supplied script found in the `contrib/tracking_module_usage` directory: 
   ```bash
   [root@host lmod-tracking]# ./analyzeLmodDB --sqlPattern '%beast%' counts

   Module path                               Syshost    Distinct Users
   -----------                               -------    --------------
   /path/to/conda/beast.lua    ['%']                   1
   
   
   Number of entries:  1
   
   Time:  0:00:13.689646
   ```
   ```bash
   [root@host lmod-tracking]# ./analyzeLmodDB --sqlPattern '%beast%' usernames

   Module path                               Syshost    User Name
   -----------                               -------    ---------
   /path/to/conda/beast.lua    ['%']      suepeter
   ```
   ```bash
   [root@host lmod-tracking]# ./analyzeLmodDB --sqlPattern 'suepeter' modules_used_by

   Module path                                                                                       Syshost    User Name
   -----------                                                                                       -------    ---------
   /path/to/conda/beast.lua                                                            ['%']      suepeter
   /path/to/spack/linux-rocky9-x86_64/Core/gcc-runtime/11.3.1-pdjx7f4.lua              ['%']      suepeter
   /path/to/spack/linux-rocky9-x86_64/Core/gcc/13.2.0-tviiimi.lua                      ['%']      suepeter
   /path/to/spack/linux-rocky9-x86_64/Core/glibc/2.34-kwsgimo.lua                      ['%']      suepeter
   /path/to/spack/linux-rocky9-x86_64/Core/gmp/6.3.0-q27rc3u.lua                       ['%']      suepeter
   /path/to/spack/linux-rocky9-x86_64/Core/mpc/1.3.1-z6el743.lua                       ['%']      suepeter
   /path/to/spack/linux-rocky9-x86_64/Core/mpfr/4.2.1-sq6ffnk.lua                      ['%']      suepeter
   /path/to/spack/linux-rocky9-x86_64/Core/openjdk/17.0.8.1_1-usumfss.lua              ['%']      suepeter
   /path/to/spack/linux-rocky9-x86_64/Core/openmpi/5.0.8.lua                           ['%']      suepeter
   /path/to/spack/linux-rocky9-x86_64/Core/snpeff/2017-11-24-lnzhkx5.lua               ['%']      suepeter
   /path/to/spack/linux-rocky9-x86_64/Core/zlib/1.3.1-ffl5dxu.lua                      ['%']      suepeter
   /path/to/spack/linux-rocky9-x86_64/Core/zstd/1.5.6-yucvkmw.lua                      ['%']      suepeter
   /path/to/spack/linux-rocky9-x86_64/openmpi/5.0.8-xnlxjsg/Core/ctffind/4.1.14.lua    ['%']      suepeter
   /path/to/spack/linux-rocky9-x86_64/openmpi/5.0.8-xnlxjsg/Core/py-topaz/0.2.4.lua    ['%']      suepeter
   /path/to/spack/linux-rocky9-x86_64/openmpi/5.0.8-xnlxjsg/Core/relion/5.0.0.lua      ['%']      suepeter
   
   
   Number of entries:  15
   
   Time:  0:00:10.599061
   ```

---

## Conclusion

---

## See Also
- Lmod GitHub: https://github.com/TACC/Lmod/
- Tracking MOdule Usage: https://lmod.readthedocs.io/en/latest/300_tracking_module_usage.html
- Using the Database: https://github.com/TACC/Lmod/tree/main/contrib/tracking_module_usage/gen_2
- ModuleRC file: https://lmod.readthedocs.io/en/latest/093_modulerc.html

- PyMySQL Github: https://github.com/PyMySQL/PyMySQL
- PyMySQL Home: https://pymysql.readthedocs.io/en/latest/index.html

`/usr/share/lmod/etc/rc` (`LMOD_MODULERCFILE`) is the way Lmod supports “modulerc” (aka rc.lua) files (Lua scripts) which won't be used for usage tracking, but can:
- Mark one version as default (module_version("1.2.3","default")),
- Define aliases/hidden modules
- Control naming conventions on a system or per‐user basis

Here's what output from the `module` command should look like on a compute node:
```bash
[suepeter@test-host ~]$ module
05:55:10


Modules based on Lua: Version 8.7.55 2024-12-13 12:24 -07:00
    by Robert McLay mclay@tacc.utexas.edu

module [options] sub-command [args ...]

Help sub-commands:
  help                              prints this message
  help                module [...]  print help message from module(s)

Loading/Unloading sub-commands:
  load | add          module [...]  load module(s)
  try-load | try-add  module [...]  Add module(s), do not complain if not found
  del | unload        module [...]  Remove module(s), do not complain if not found
  swap | sw | switch  m1 m2         unload m1 and load m2
  purge                             unload all modules
  refresh                           reload aliases from current list of modules.
  update                            reload all currently loaded modules.

Listing / Searching sub-commands:
  list                              List loaded modules
  list                s1 s2 ...     List loaded modules that match the pattern
  avail | av                        List available modules
  avail | av          string        List available modules that contain "string".
  category | cat                    List all categories
  category | cat      s1 s2 ...     List all categories that match the pattern and display their modules
  overview | ov                     List all available modules by short names with number of versions
  overview | ov       string        List available modules by short names with number of versions that contain "string"
  spider                            List all possible modules
  spider              module        List all possible version of that module file
  spider              string        List all module that contain the "string".
  spider              name/version  Detailed information about that version of the module.
  whatis              module        Print whatis information about module
  keyword | key       string        Search all name and whatis that contain "string".

Searching with Lmod:
  All searching (spider, list, avail, keyword) support regular expressions:


  -r spider           '^p'          Finds all the modules that start with `p' or `P'
  -r spider           mpi           Finds all modules that have "mpi" in their name.
  -r spider           'mpi$         Finds all modules that end with "mpi" in their name.

Handling a collection of modules:
  save | s                          Save the current list of modules to a user defined "default" collection.
  save | s            name          Save the current list of modules to "name" collection.
  reset                             The same as "restore system"
  restore | r                       Restore modules from the user's "default" or system default.
  restore | r         name          Restore modules from "name" collection.
  restore             system        Restore module state to system defaults.
  savelist                          List of saved collections.
  describe | mcc      name          Describe the contents of a module collection.
  disable             name          Disable (i.e. remove) a collection.

Deprecated commands:
  getdefault          [name]        load name collection of modules or user's "default" if no name given.
                                    ===> Use "restore" instead  <====
  setdefault          [name]        Save current list of modules to name if given, otherwise save as the default list for you the user.
                                    ===> Use "save" instead. <====

Miscellaneous sub-commands:
  is-loaded           modulefile    return a true status if module is loaded
  is-avail            modulefile    return a true status if module can be loaded
  show                modulefile    show the commands in the module file.
  use [-a]            path          Prepend or Append path to MODULEPATH.
  unuse               path          remove path from MODULEPATH.
  tablelist                         output list of active modules as a lua table.

Important Environment Variables:
  LMOD_COLORIZE                     If defined to be "YES" then Lmod prints properties and warning in color.


Lmod Web Sites

  Documentation:    https://lmod.readthedocs.org
  GitHub:           https://github.com/TACC/Lmod
  SourceForge:      https://lmod.sf.net
  TACC Homepage:    https://www.tacc.utexas.edu/research-development/tacc-projects/lmod

  To report a bug please read https://lmod.readthedocs.io/en/latest/075_bug_reporting.html
```

---

## Archives
1. Edit `/etc/rsyslog.conf` on a test node. Incorporate the changes you made to the `SitePackage.lua` file within the `report_loads()` function. We're tagging (`-t`) our `logger` calls with `GoodLawd_ModuleUsage`.
   ```bash
   [root@client ~]# vi /etc/rsyslog.conf

   42 # Lmod module usage tracking (MUTT) - suepeter - 2025-10-24
   43 if $programname contains 'GoodLawd_ModuleUsage' then @host.here.there.com
   44 & stop
   ```
   ```bash
   [root@host lmod-tracking]# python3 -B /opt/lmod-tracking/store_module_data -D /var/log/module-usage.log
   [WARN] Missing host in line: Nov  4 16:38:21 client.here.there.com ModuleUsage TEST MODULE LOG MESSAGE client.here.there.com
   [WARN] Missing host in line: Nov  4 16:39:44 client.here.there.com ModuleUsage TEST MODULE LOG MESSAGE client.here.there.com
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'openjdk/17.0.8.1_1-usumfss', 'path': '/path/to/spack/linux-rocky9-x86_64/Core/openjdk/17.0.8.1_1-usumfss.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762354382.335834'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'glibc/2.34-kwsgimo', 'path': '/path/to/spack/linux-rocky9-x86_64/Core/glibc/2.34-kwsgimo.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762354382.402238'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'beast', 'path': '/path/to/conda/beast.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762354382.336788'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'snpeff/2017-11-24-lnzhkx5', 'path': '/path/to/spack/linux-rocky9-x86_64/Core/snpeff/2017-11-24-lnzhkx5.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762354382.336078'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'gcc/13.2.0-tviiimi', 'path': '/path/to/spack/linux-rocky9-x86_64/Core/gcc/13.2.0-tviiimi.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762354382.408591'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'zstd/1.5.6-yucvkmw', 'path': '/path/to/spack/linux-rocky9-x86_64/Core/zstd/1.5.6-yucvkmw.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762354382.407864'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'relion/5.0.0', 'path': '/path/to/spack/linux-rocky9-x86_64/openmpi/5.0.8-xnlxjsg/Core/relion/5.0.0.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762354382.334505'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'ctffind/4.1.14', 'path': '/path/to/spack/linux-rocky9-x86_64/openmpi/5.0.8-xnlxjsg/Core/ctffind/4.1.14.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762354382.333316'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'gmp/6.3.0-q27rc3u', 'path': '/path/to/spack/linux-rocky9-x86_64/Core/gmp/6.3.0-q27rc3u.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762354382.403320'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'mpc/1.3.1-z6el743', 'path': '/path/to/spack/linux-rocky9-x86_64/Core/mpc/1.3.1-z6el743.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762354382.405168'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'mpfr/4.2.1-sq6ffnk', 'path': '/path/to/spack/linux-rocky9-x86_64/Core/mpfr/4.2.1-sq6ffnk.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762354382.404996'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'zlib/1.3.1-ffl5dxu', 'path': '/path/to/spack/linux-rocky9-x86_64/Core/zlib/1.3.1-ffl5dxu.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762354382.406419'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'openmpi/5.0.8', 'path': '/path/to/spack/linux-rocky9-x86_64/Core/openmpi/5.0.8.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762354382.313712'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'py-topaz/0.2.4', 'path': '/path/to/spack/linux-rocky9-x86_64/openmpi/5.0.8-xnlxjsg/Core/py-topaz/0.2.4.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762354382.334122'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'gcc-runtime/11.3.1-pdjx7f4', 'path': '/path/to/spack/linux-rocky9-x86_64/Core/gcc-runtime/11.3.1-pdjx7f4.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762354382.402361'}
   [WARN] Missing host in line: Nov  5 11:26:25 test-host-2 ModuleUsage[2099772]: HAKUNA MATATA from test-host-2.here.there.com
   [WARN] Missing host in line: Nov  5 13:53:30 client GoodLawdModuleUsageTracking[1006264]: test from client.here.there.com
   [WARN] Missing host in line: Nov  5 13:53:41 client ModuleUsage[1006311]: test from client.here.there.com
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'openjdk/17.0.8.1_1-usumfss', 'path': '/path/to/spack/linux-rocky9-x86_64/Core/openjdk/17.0.8.1_1-usumfss.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762376451.094294'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'mpfr/4.2.1-sq6ffnk', 'path': '/path/to/spack/linux-rocky9-x86_64/Core/mpfr/4.2.1-sq6ffnk.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762376451.134658'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'zlib/1.3.1-ffl5dxu', 'path': '/path/to/spack/linux-rocky9-x86_64/Core/zlib/1.3.1-ffl5dxu.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762376451.135937'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'ctffind/4.1.14', 'path': '/path/to/spack/linux-rocky9-x86_64/openmpi/5.0.8-xnlxjsg/Core/ctffind/4.1.14.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762376451.092174'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'zstd/1.5.6-yucvkmw', 'path': '/path/to/spack/linux-rocky9-x86_64/Core/zstd/1.5.6-yucvkmw.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762376451.137247'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'snpeff/2017-11-24-lnzhkx5', 'path': '/path/to/spack/linux-rocky9-x86_64/Core/snpeff/2017-11-24-lnzhkx5.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762376451.094536'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'gcc/13.2.0-tviiimi', 'path': '/path/to/spack/linux-rocky9-x86_64/Core/gcc/13.2.0-tviiimi.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762376451.137976'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'relion/5.0.0', 'path': '/path/to/spack/linux-rocky9-x86_64/openmpi/5.0.8-xnlxjsg/Core/relion/5.0.0.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762376451.093205'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'beast', 'path': '/path/to/conda/beast.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762376451.095051'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'gmp/6.3.0-q27rc3u', 'path': '/path/to/spack/linux-rocky9-x86_64/Core/gmp/6.3.0-q27rc3u.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762376451.133130'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'gcc-runtime/11.3.1-pdjx7f4', 'path': '/path/to/spack/linux-rocky9-x86_64/Core/gcc-runtime/11.3.1-pdjx7f4.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762376451.132300'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'openmpi/5.0.8', 'path': '/path/to/spack/linux-rocky9-x86_64/Core/openmpi/5.0.8.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762376451.073484'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'glibc/2.34-kwsgimo', 'path': '/path/to/spack/linux-rocky9-x86_64/Core/glibc/2.34-kwsgimo.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762376451.132175'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'py-topaz/0.2.4', 'path': '/path/to/spack/linux-rocky9-x86_64/openmpi/5.0.8-xnlxjsg/Core/py-topaz/0.2.4.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762376451.092826'}
   [INFO] Parsed line: {'user': 'suepeter', 'module': 'mpc/1.3.1-z6el743', 'path': '/path/to/spack/linux-rocky9-x86_64/Core/mpc/1.3.1-z6el743.lua', 'jobid': 'interactive', 'syshost': 'client', 'date': '1762376451.134825'}
     --> Trying to connect to database
   Database host:localhost
   Database user:DBUser
   Database pass:
   Database name:GoodLawdlmod
   ```

---

<details>
<summary><b>Tags</b></summary>
lmod module
</details>
