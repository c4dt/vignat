-- Run search to find the point at which the middle box start
-- loosing 1% of the packets

package.path = package.path ..";?.lua;test/?.lua;app/?.lua;../?.lua"

require "Pktgen";

-- define packet sizes to test
-- local pkt_sizes		= { 64, 128, 256, 512, 1024, 1280, 1518 };
local pkt_sizes		= { 64};--, 128};

local flows_nums = { 20000, 25000, 30000, 46500, 48500, 58200, 58400 };   -- { 5000, 10000, 15000, 2000 } -- { 45000, 50000, 55000, 56000, 57000, 58500 }; -- 1000, 10000, 20000, 30000, 40000, 50000, 55000, 58000, 58500, 59000, 60000, 61000 };

-- Time in seconds to transmit for
local duration		= 40000;
--local confirmDuration	= 80000;
local pauseTime		= 2000;

-- the part to start from
local strtprt_int = 1000;


local num_bin_steps = 7;

local srcUDPPort = "1234";

-- define the ports in use
local recvport		= "0";
local sendport		= "1";

-- ip addresses to use
local dstip		= "192.168.2.10";
local srcip		= "192.168.3.5";
local netmask		= "/24";

local recvport_dst_mac = "00:1E:67:92:29:6C"
local sendport_dst_mac = "00:1E:67:92:29:6D"

local initialRate	= 50 ;

local function setupTraffic(numFlows)
	local portStart = tostring(strtprt_int);
	local portEnd = tostring(strtprt_int + numFlows);
	pktgen.set_ipaddr(sendport, "dst", dstip);
	pktgen.set_ipaddr(sendport, "src", srcip..netmask);
	pktgen.set_mac(sendport, sendport_dst_mac);

	pktgen.set_ipaddr(recvport, "dst", srcip);
	pktgen.set_ipaddr(recvport, "src", dstip..netmask);
	pktgen.set_mac(recvport, recvport_dst_mac);

	pktgen.set_proto(sendport..","..recvport, "udp");
	-- set Pktgen to send continuous stream of traffic
	pktgen.set(sendport, "count", 0);

	pktgen.dst_port(sendport, "start", portStart);
	pktgen.dst_port(sendport, "inc", "1");
	pktgen.dst_port(sendport, "min", portStart);
	pktgen.dst_port(sendport, "max", portEnd);

	pktgen.src_port(sendport, "start", srcUDPPort);
	pktgen.src_port(sendport, "inc", "0");
	pktgen.src_port(sendport, "min", srcUDPPort);
	pktgen.src_port(sendport, "max", srcUDPPort);

	pktgen.dst_ip(sendport, "start", dstip);
	pktgen.dst_ip(sendport, "inc", "0");
	pktgen.dst_ip(sendport, "min", dstip);
	pktgen.dst_ip(sendport, "max", dstip);

	pktgen.src_ip(sendport, "start", srcip);
	pktgen.src_ip(sendport, "inc", "0");
	pktgen.src_ip(sendport, "min", srcip);
	pktgen.src_ip(sendport, "max", srcip);

	pktgen.dst_mac(sendport, "start", sendport_dst_mac);
	pktgen.dst_mac(sendport, "inc", "0");
	pktgen.dst_mac(sendport, "min", sendport_dst_mac);
	pktgen.dst_mac(sendport, "max", sendport_dst_mac);

	pktgen.range(sendport, "on");
end

local function runTrial(numFlows, pkt_size, rate, duration, count)
	local num_tx, num_rx, num_dropped;

	pktgen.clr();
	pktgen.set(sendport, "rate", rate);
	pktgen.set(sendport, "size", pkt_size);

	pktgen.start(sendport);
	print("R trial " .. count .. ". % rt: " .. rate .. " nflws: " .. numFlows .. ". pkts: " .. pkt_size .. ". Dur (mS):" .. duration);
	pktgen.delay(duration);
	pktgen.stop(sendport);
	

	pktgen.delay(pauseTime);

	statTx = pktgen.portStats(sendport, "port")[tonumber(sendport)];
	statRx = pktgen.portStats(recvport, "port")[tonumber(recvport)];
	num_tx = statTx.opackets;
	num_rx = statRx.ipackets;
	num_dropped = (num_tx - num_rx)/num_tx;

	print("Tx: " .. num_tx .. ". Rx: " .. num_rx .. ". Drop: " .. num_dropped .. ".");
	--file:write(numFlows .. " " .. pkt_size .. " " .. rate .. " "
	--        .. num_tx .. " " .. num_rx .. " " .. duration .. "\n");
	pktgen.delay(pauseTime);

	return num_dropped, num_tx;
end

local function runThroughputTest(numFlows, pkt_size)
	local num_dropped, max_rate, min_rate,
 	      trial_rate, abs_min_rate, abs_max_rate, num_tx;
	local reg50_step, reg100_step;
	local steps_to50, steps_to100;

	abs_max_rate = 100;
	abs_min_rate = 1;
	max_rate = abs_max_rate;
	min_rate = abs_min_rate;
	trial_rate = initialRate;
	tot_count = 1;

	for count=1, num_bin_steps, 1
	do		
		num_dropped, num_tx = runTrial(numFlows, pkt_size, trial_rate, duration, tot_count);
		tot_count = tot_count + 1;
		if num_dropped < 0.01
		then
			min_rate = trial_rate;
		else
			max_rate = trial_rate;
		end
		trial_rate = min_rate + ((max_rate - min_rate)/2);
	end
	file:write(numFlows .. " " .. pkt_size .. " " .. trial_rate .. " " .. num_tx .. "\n");
end

function main()
	file = io.open("multi-flows.txt", "w");
	runTrial(10000, 64, 1, 10000, "heatup");
	for _,numFlows in pairs(flows_nums)
	do
		setupTraffic(numFlows);
		for _,size in pairs(pkt_sizes)
		do
			runThroughputTest(numFlows, size);
		end
	end
	file:close();
end


main();
os.exit();
