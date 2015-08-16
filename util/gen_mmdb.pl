use MaxMind::DB::Writer::Tree;
use Net::Works::Network;
my $tree = MaxMind::DB::Writer::Tree->new(
    ip_version    => 4,
    record_size   => 24,
    database_type => 'MMDB',
    description   => {
        en => 'My MaxMindDB',
    },
    map_key_type_callback => sub { 'utf8_string' },
);
open my $rfh, "<", $ARGV[0];
while (<$rfh>) {
    chomp;
    my ( $start_ip, $end_ip, $country, $province, $city, $district, $isp, $desc ) = split /\t/, $_;
    my @subnets = Net::Works::Network->range_as_subnets($start_ip, $end_ip);
    for my $subnet (@subnets) {
        $tree->insert_network($subnet, {
            country  => $country,
            province => $province,
            city     => $city,
            district => $district,
            isp      => $isp,
            desc     => $desc,
        });
    }
}
open my $fh, '>', "ipdata.mmdb";
$tree->write_tree($fh);
