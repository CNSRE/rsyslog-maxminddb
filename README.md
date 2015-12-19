# rsyslog-maxminddb

日志解析处理中，对 IP 归属地的解析是很常见的需求。在 ELKstack 中就可以通过 logstash-filter-geoip 插件解析 IP，kibana tilemap 做经纬度可视化。不过 GeoIP 库在国内准确率较低，一般认为不足 70%，且 logstash-filter-geoip 插件的效率也不高，在高流量场合达不到性能要求。

MaxMindDB 是 MaxMind 公司继 GeoIP 之后推出的新一代 IP 地址库[格式](http://maxmind.github.io/MaxMind-DB/)。对应的公开版本地址库叫 GeoLite2。

和 GeoIP 相比，MaxMindDB 有两个重要优势：

1. 同为 C 接口，新格式的性能也提升了 4 到 6 倍；
2. MaxMindDB 提供了自己生成私有地址库的写入工具。

为完成高性能高精确度的 IP 归属地解析，选择在 Rsyslog 项目基础上，利用 C 语言版本的 libmaxminddb 接口开发了这个 Message Modification Module，目前已在新浪线上稳定运行数月。

## 编译

1. 下载 rsyslog 源码包：
```
git clone https://github.com/rsyslog/rsyslog.git
```
2. 复制本仓库源码文件到 rsyslog 源码目录内：
```
cp -r src/contrib/mmdblookup ../rsyslog/contrib/
cp src/configure.ac ../rsyslog/
cp src/Makefile.am ../rsyslog/
# 可以包括测试用例一起
# cp src/tests ../rsyslog/
```
3. 编译 rsyslog：
```
export PKG_CONFIG_PATH=/lib64/pkgconfig/
yum install -y libestr liblogging libmaxminddb-devel
yum install -y git-core valgrind autoconf automake flex bison json-c-devel libuuid-devel libgcrypt-devel zlib-devel openssl-devel libcurl-devel gnutls-devel mysql-devel postgresql-devel libdbi-dbd-mysql libdbi-devel net-snmp-devel
autoconf
./configure --enable-mmdblookup --enable-elasticsearch --enable-mmjsonparse --***(其他你想加上的参数)
```

或者通过 rpmbuild 方式打包：
```
git clone https://github.com/rsyslog/rsyslog-pkg-rhel-centos
cp util/rsyslog.spec ./rsyslog-pkg-rhel-centos/rpmbuild/SPECS/v8-stable.spec
rpmbuild -bb ./rsyslog-pkg-rhel-centos/rpmbuild/SPECS/v8-stable.spec
```

## 部署使用

1. 安装依赖：
```
wget ftp://ftp.pbone.net/mirror/ftp.pramberger.at/systems/linux/contrib/rhel6/x86_64/libmaxminddb-1.0.4-1.el6.pp.x86_64.rpm
rpm -ivh libmaxminddb-1.0.4-1.el6.pp.x86_64.rpm
```
2. 可以直接使用之前编译所得的完整 rsyslog，也可以单独复制 mmdblookup.so 文件到 /lib64/rsyslog 目录下。

## 配置示例


```
module( load="imfile" )
module( load="mmdblookup" )
module( load="mmjsonparse" )

input (
	type="imfile"
	File="/tmp/access.log"
	addMetadata="off"
	Severity="info"
	Facility="user"
	tag="test"
	ruleset="test"
)

template( type="string" string="{\"@timestamp\":\"%timereported:::date-rfc3339%\",\"host\":\"%hostname%\",\"geoip2\":%$!iplocation%,%msg:7:$%" name="clientlog" )
ruleset ( name="test"){
	action( type="mmjsonparse" )
	if ( $parsesuccess == "OK" ) then {
	    action( type="mmdblookup" mmdbfile="/etc/rsyslog.d/GeoLite2-City.mmdb" fields=["!country","!city","!continent"] key="!clientip" )
	    set $!iplocation!country2 = $!iplocation!country!names!zh-CN;
	    set $!iplocation!city2 = $!iplocation!city!names!zh-CN;
	    set $!iplocation!continent2 = $!iplocation!continent!names!zh-CN;
	    unset $!iplocation!country;
	    unset $!iplocation!city;
	    unset $!iplocation!continent;
	    action(type="omfwd" Target="10.211.55.4" port="514" Protocol="tcp" template="clientlog")
	    stop
	}

}

```
#cat /root/a
@cee:{"clientip":"202.106.0.2","os_ver":"ios8","weibo_ver":"5.4.0","uid":1234567890,"rtt":0.123456,"error_code":-10005,"error_msg":"你以为我会告诉你么"}
#cat /root/a > /tmp/access
```

```

生成的 logstash 记录示例如下：

```
{
       "message" => "{\"@timestamp\":\"2015-12-16T23:00:38.876407+08:00\",\"host\":\"localhost\",\"geoip2\":{ \"country2\": \"中国\", \"city2\": \"北京\", \"continent2\": \"亚洲\" },\"clientip\":\"202.106.0.2\",\"os_ver\":\"ios8\",\"weibo_ver\":\"5.4.0\",\"uid\":1234567890,\"rtt\":0.123456,\"error_code\":-10005,\"error_msg\":\"你以为我会告诉你么\"} ",
      "@version" => "1",
    "@timestamp" => "2015-12-16T15:00:38.905Z",
          "host" => "10.211.55.4"
```

## MaxMindDB 文件生成

本仓库自带一个生成 MaxMindDB 地址库的示例程序。程序假设你有一个ipdata.csv文件，每行记录的是一个IP段的开始IP，结束IP，归属国家、省、市、街道、运营商、其他注释。

程序使用 MaxMind::DB::Writer 模块，请先通过 cpan 安装：

```
yum install -y perl-libs perl-corelist
wget https://cpanmin.us -O /usr/sbin/cpanm
chmod +x /usr/sbin/cpanm
cpanm MaxMind::DB::Writer
perl util/gen_mmdb.pl ipdata.csv
```
