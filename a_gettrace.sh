adb shell " cd /sys/kernel/debug/tracing/per_cpu/cpu0;
	     cat ./trace > /data/trace_cpu0.txt;
	    cd /sys/kernel/debug/tracing;
	    cat ./trace > /data/trace.txt;"
adb pull /data/trace.txt ./trace.txt
adb pull /data/trace_cpu0.txt ./trace_cpu0.txt

