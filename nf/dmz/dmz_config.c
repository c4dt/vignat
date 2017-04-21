#include <getopt.h>
#include <inttypes.h>

#if KLEE_VERIFICATION
	#include "stubs/rte_stubs.h"
#else
	// DPDK needs these but doesn't include them. :|
	#include <linux/limits.h>
	#include <sys/types.h>

	#include <rte_common.h>
	#include <rte_ethdev.h>
#endif

#include <cmdline_parse_etheraddr.h>
#include <cmdline_parse_ipaddr.h>

#include "dmz_config.h"
#include "nf_util.h"
#include "nf_log.h"


#define PARSE_ERROR(format, ...) \
		dmz_config_cmdline_print_usage(); \
		rte_exit(EXIT_FAILURE, format, ##__VA_ARGS__);


static uintmax_t
dmz_config_parse_int(const char* str, const char* name, int base, char next) {
	char* temp;
	intmax_t result = strtoimax(str, &temp, base);

	// There's also a weird failure case with overflows, but let's not care
	if(temp == str || *temp != next) {
		rte_exit(EXIT_FAILURE, "Error while parsing '%s': %s\n", name, str);
	}

	return result;
}

void dmz_config_init(struct nat_config* config,
                     int argc, char** argv)
{
	unsigned nb_devices = rte_eth_dev_count();

	struct option long_options[] = {
		{"inter-dev",		required_argument,	NULL, 'a'},
		{"dmz-dev",		required_argument,	NULL, 'b'},
		{"intra-dev",		required_argument,	NULL, 'c'},
		{"inter-addr",		required_argument,	NULL, 'd'},
		{"inter-mask",		required_argument,	NULL, 'e'},
		{"dmz-addr",		required_argument,	NULL, 'f'},
		{"dmz-mask",		required_argument,	NULL, 'g'},
		{"intra-addr",		required_argument,	NULL, 'h'},
		{"intra-mask",		required_argument,	NULL, 'i'},
		{"eth-dest",		required_argument,	NULL, 'j'},
		{"expire",		required_argument,	NULL, 'k'},
		{"max-flows",		required_argument,	NULL, 'l'},
		{NULL, 			0,			NULL, 0  }
	};

	// Set the devices' own MACs
	for (uint8_t device = 0; device < nb_devices; device++) {
		rte_eth_macaddr_get(device, &(config->device_macs[device]));
	}

	int opt;
	while ((opt = getopt_long(argc, argv, "m:e:t:i:l:f:p:s:w:", long_options, NULL)) != EOF) {
		unsigned device;
		switch (opt) {
			case 'm':
				device = nat_config_parse_int(optarg, "eth-dest device", 10, ',');
				if (device >= nb_devices) {
					PARSE_ERROR("eth-dest: device %d >= nb_devices (%d)\n", device, nb_devices);
				}

				optarg += 2;
				if (cmdline_parse_etheraddr(NULL, optarg, &(config->endpoint_macs[device]), sizeof(int64_t)) < 0) {
					PARSE_ERROR("Invalid MAC address: %s\n", optarg);
				}
				break;

			case 't':
				config->expiration_time = nat_config_parse_int(optarg, "exp-time", 10, '\0');
				if (config->expiration_time == 0) {
					PARSE_ERROR("Expiration time must be strictly positive.\n");
				}
				break;

			case 'i':;
				struct cmdline_token_ipaddr tk;
				tk.ipaddr_data.flags = CMDLINE_IPADDR_V4;

				struct cmdline_ipaddr res;
				if (cmdline_parse_ipaddr((cmdline_parse_token_hdr_t*) &tk, optarg, &res, sizeof(res)) < 0) {
					PARSE_ERROR("Invalid external IP address: %s\n", optarg);
				}

				config->external_addr = res.addr.ipv4.s_addr;
				break;

			case 'l':
				config->lan_main_device = nat_config_parse_int(optarg, "lan-dev", 10, '\0');
				if (config->lan_main_device >= nb_devices) {
					PARSE_ERROR("Main LAN device does not exist.\n");
				}
				break;

			case 'f':
				config->max_flows = nat_config_parse_int(optarg, "max-flows", 10, '\0');
				if (config->max_flows <= 0) {
					PARSE_ERROR("Flow table size must be strictly positive.\n");
				}
				break;

			case 's':
				config->start_port = nat_config_parse_int(optarg, "start-port", 10, '\0');
				break;

			case 'w':
				config->wan_device = nat_config_parse_int(optarg, "wan-dev", 10, '\0');
				if (config->wan_device >= nb_devices) {
					PARSE_ERROR("WAN device does not exist.\n");
				}
				break;
		}
	}

	// Reset getopt
	optind = 1;
}

void dmz_config_cmdline_print_usage(void)
{
	printf("Usage:\n"
		"[DPDK EAL options] --\n"
		"\t--eth-dest <device>,<mac>: MAC address of the endpoint linked to a device.\n"
		"\t--expire <time>: flow expiration time.\n"
		"\t--{inter,dmz,intra}-dev <device>: set device.\n"
		"\t--{inter,dmz,intra}-addr <addr>: set block address.\n"
		"\t--{inter,dmz,intra}-mask <mask>: set block mask.\n"
		"\t--max-flows <n>: flow table capacity.\n"
	);
}

void dmz_print_config(struct dmz_config* config)
{
	NF_INFO("\n--- DMZ Config ---\n");

	NF_INFO("Internet device: %" PRIu8, config->inter_device);
	NF_INFO("DMZ device: %" PRIu8, config->dmz_device);
	NF_INFO("Intranet device: %" PRIu8, config->intra_device);

	char* inter_addr_str = nf_ipv4_to_str(config->inter_block_addr);
	char* inter_mask_str = nf_ipv4_to_str(config->inter_block_mask);
	NF_INFO("Internet block address: %s", inter_addr_str);
	NF_INFO("Internet block mask: %s", inter_mask_str);
	free(inter_addr_str);
	free(inter_mask_str);

	char* dmz_addr_str = nf_ipv4_to_str(config->dmz_block_addr);
	char* dmz_mask_str = nf_ipv4_to_str(config->dmz_block_mask);
	NF_INFO("DMZ block address: %s", dmz_addr_str);
	NF_INFO("DMZ block mask: %s", dmz_mask_str);
	free(dmz_addr_str);
	free(dmz_mask_str);

	char* intra_addr_str = nf_ipv4_to_str(config->intra_block_addr);
	char* intra_mask_str = nf_ipv4_to_str(config->intra_block_mask);
	NF_INFO("Intranet block address: %s", intra_addr_str);
	NF_INFO("Intranet block mask: %s", intra_mask_str);
	free(intra_addr_str);
	free(intra_mask_str);

	uint8_t nb_devices = rte_eth_dev_count();
	for (uint8_t dev = 0; dev < nb_devices; dev++) {
		char* dev_mac_str = nf_mac_to_str(&(config->device_macs[dev]));
		char* end_mac_str = nf_mac_to_str(&(config->endpoint_macs[dev]));

		NF_INFO("Device %" PRIu8 " own-mac: %s, end-mac: %s", dev, dev_mac_str, end_mac_str);

		free(dev_mac_str);
		free(end_mac_str);
	}

	NF_INFO("Expiration time: %" PRIu32, config->expiration_time);
	NF_INFO("Max flows: %" PRIu16, config->max_flows);

	NF_INFO("\n--- --- ------ ---\n");
}
