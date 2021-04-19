#!/bin/bash

# Version of cat5tv-sbctest this is based upon
c5ver="2.2"

start=`date +%s`

if [[ ! -e /usr/local/bin/nems-info ]]; then
  echo "Requires NEMS Linux."
  exit 1
fi

# Check if NEMS has been initialized, don't benchmark if not
  nemsinit=`/usr/local/bin/nems-info init`
  if [[ $nemsinit == 0 ]]; then
    echo "NEMS hasn't been initialized."
    exit 1
  fi

# Do not run if watchdog is connected
# High load from benchmark could cause watchdog to believe the board is hung, and reboot itself
  piwatcher=`/usr/local/bin/nems-info piwatcher`
  pivoyager=`/usr/local/bin/nems-info pivoyager`
  if [[ $piwatcher == 1 ]] || [[ $pivoyager == 1 ]]; then
    echo "Watchdog is connected. Benchmark will not run."
    exit 1
  fi

# Good to proceed, begin benchmark

# Set a runtime
if [[ -f /var/log/nems/benchmarks/runtime ]]; then
  lastruntime=`cat /var/log/nems/benchmarks/runtime`
  if [ "$lastruntime" -gt "18000" ]; then
    # Don't run weekly benchmark on boards that take longer than 10 minutes to do so
    echo "Benchmarks take too long on this board. Aborting."
    echo "Stats for this board will be based on first run."
    exit 1
  fi
  thisruntime=$(($lastruntime+120)) # +2 minutes from the last runtime
else
  thisruntime=18000 # 10 minutes
fi
plannedend=$(($start + $thisruntime))

# Schedule downtime on CPU Load notifications for 5 hours during benchmarks
/usr/bin/printf "[%lu] SCHEDULE_SVC_DOWNTIME;NEMS;Current Load;$start;$plannedend;0;0;$thisruntime;NEMS Linux;Weekly Benchmarks Running\n" $start > /usr/local/nagios/var/rw/nagios.cmd

echo "NEMS System Benchmark... Please Wait (may take a while)."

tmpdir=`mktemp -d -p /usr/local/share/`

echo "NEMS System Benchmark" > $tmpdir/nems-benchmark.log
date >> $tmpdir/nems-benchmark.log
printf "NEMS Version: " >> $tmpdir/nems-benchmark.log
ver=$(/usr/local/bin/nems-info nemsver)
echo $ver >> $tmpdir/nems-benchmark.log

echo "Using algorithms from cat5tv-sbctest v$c5ver" >> $tmpdir/nems-benchmark.log
prog=$(which 7za || which 7zr)
echo "" >> $tmpdir/nems-benchmark.log
printf "LZMA Benchmarks Provided By: " >> $tmpdir/nems-benchmark.log
$prog 2>&1 | head -n3 >> $tmpdir/nems-benchmark.log
echo "" >> $tmpdir/nems-benchmark.log

printf "Platform: " >> $tmpdir/nems-benchmark.log
platform=$(/usr/local/bin/nems-info platform-name)
echo $platform >> $tmpdir/nems-benchmark.log

printf "\nHardware Revision: " >> $tmpdir/nems-benchmark.log
/usr/local/bin/nems-info hwver >> $tmpdir/nems-benchmark.log
printf "NEMS ID: " >> $tmpdir/nems-benchmark.log
/usr/local/bin/nems-info hwid >> $tmpdir/nems-benchmark.log

printf "System Uptime: " >> $tmpdir/nems-benchmark.log
/usr/bin/uptime >> $tmpdir/nems-benchmark.log

printf "LAN IP: " >> $tmpdir/nems-benchmark.log
/usr/local/bin/nems-info ip >> $tmpdir/nems-benchmark.log

echo "---------------------------------" >> $tmpdir/nems-benchmark.log

if [[ ! -d /var/log/nems/benchmarks ]]; then
  mkdir -p /var/log/nems/benchmarks
fi

# Run the tests
cores=$(nproc --all)

echo "Number of threads: $cores" >> $tmpdir/nems-benchmark.log

cd $tmpdir

printf "Performing LZMA Benchmark: " >> $tmpdir/nems-benchmark.log
if [[ -z $prog ]]; then
  apt update && apt -y install p7zip
  prog=$(which 7za || which 7zr)
fi

if [[ ! -z $prog ]]; then

  # Multithreaded test
  "$prog" b > $tmpdir/7z.log
  result7z=$(awk -F" " '/^Tot:/ {print $4}' <$tmpdir/7z.log | tr '\n' ', ' | sed 's/,$//')
  echo "Done." >> $tmpdir/nems-benchmark.log
  echo "Multi-Threaded Benchmark Result:     $result7z" >> $tmpdir/nems-benchmark.log
  echo $result7z > /var/log/nems/benchmarks/7z-multithread


  # Average Single Thread benchmark
    # Get the total result from first CPU core
      taskset -c 0 "$prog" b > $tmpdir/7z.log
      result1=$(awk -F" " '/^Tot:/ {print $4}' <$tmpdir/7z.log | tr '\n' ', ' | sed 's/,$//')
      cores1=$(/usr/local/share/nems/nems-scripts/benchmark-parsecores.sh 0)
    # Get the total result from last CPU core (might be big.LITTLE, or could be same core)
      lastcore=$(( $cores - 1 ))
      cores2=0
      if (( $lastcore > 0 )) && (( $cores1 < $cores )); then
        taskset -c $lastcore "$prog" b > $tmpdir/7z.log
        result2=$(awk -F" " '/^Tot:/ {print $4}' <$tmpdir/7z.log | tr '\n' ', ' | sed 's/,$//')
        cores2=$(/usr/local/share/nems/nems-scripts/benchmark-parsecores.sh $lastcore)
      else
        result2=$result1 # Single-core processor or all cores are on same chip
      fi
      # Multiply our first and last result by the number of cores on that processor
      # This assumes each core of the same processor will clock roughly the same
      # which is not literally accurate, but gives us a reasonable approximation without
      # having to benchmark each and every core.
      if (( $cores2 > 0 )); then
        average7z=$(( ( ($result1*$cores1) + ($result2*$cores2) ) / 2 ))
      else
        average7z=$(( ($result1*$cores1) ))
      fi
      echo "Single-Threaded Benchmark Result:     $average7z" >> $tmpdir/nems-benchmark.log
      echo $average7z > /var/log/nems/benchmarks/7z-singlethread

else
  echo "Can't find or install p7zip. 7z benchmark skipped." >> $tmpdir/nems-benchmark.log
fi
echo "---------------------------------" >> $tmpdir/nems-benchmark.log

# Ensure only root can write to the benchmark result files
chmod 644 -R /var/log/nems/benchmarks/

echo "Filesystem:" >> $tmpdir/nems-benchmark.log
/bin/df -h >> $tmpdir/nems-benchmark.log

echo "---------------------------------" >> $tmpdir/nems-benchmark.log

echo "Memory:" >> $tmpdir/nems-benchmark.log
/usr/bin/free -h >> $tmpdir/nems-benchmark.log

echo "---------------------------------" >> $tmpdir/nems-benchmark.log

echo "Internet Speed:" >> $tmpdir/nems-benchmark.log
disablespeedtest=`/usr/local/bin/nems-info disablespeedtest`
if [[ $disablespeedtest == 1 ]]; then
  echo "Ping: N/A ms" >> $tmpdir/nems-benchmark.log
  echo "Download: N/A Mbit/s" >> $tmpdir/nems-benchmark.log
  echo "Upload: N/A Mbit/s" >> $tmpdir/nems-benchmark.log
else
  /usr/local/share/nems/nems-scripts/speedtest --simple >> $tmpdir/nems-benchmark.log
fi

echo "---------------------------------" >> $tmpdir/nems-benchmark.log

end=`date +%s`
runtime=$((end-start))
echo "Benchmark of this benchmark: "$runtime" seconds" >> $tmpdir/nems-benchmark.log

echo $runtime > /var/log/nems/benchmarks/runtime

cat $tmpdir/nems-benchmark.log
cd /tmp
rm -rf $tmpdir

# sometime in future, get the downtime ID from livestatus and output it in place of the '1'
#/usr/bin/printf "[%lu] DEL_SVC_DOWNTIME;1\n" $end > /usr/local/nagios/var/rw/nagios.cmd

