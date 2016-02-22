#
#  Copyright 2015 Electric Cloud, Inc.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

##########################
# displayESXSummary.pl
##########################
use warnings;
use strict;

my $opts;
print "Displaying ESX Host Summary\n";
$opts->{connection_config} = q{$[connection_config]};
$opts->{host_name} = q{$[host_name]};
$opts->{live_usage} = q{$[live_usage]};
$opts->{network_info} = q{$[network_info]};
$opts->{storage_info} = q{$[storage_info]};

$[/myProject/procedure_helpers/preamble]

$gt->summary();
exit($opts->{exitcode});
