=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

=pod

=head1 NAME

Bio::EnsEMBL::RDF::Pipeline::PipeConfig::SimpleSpecies

=head1 DESCRIPTION

Simple pipeline to work on a single species for trial purposes

=cut

package Bio::EnsEMBL::RDF::Pipeline::PipeConfig::SimpleSpecies;
use strict;
use parent 'Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf';
use Bio::EnsEMBL::ApiVersion qw/software_version/;

sub default_options {
  return {
    xref => 1,
    dump_location => '', # base path for all RDF output
    release => software_version(),
    config_file => 'xref_LOD_mapping.json',
  }
}

sub pipeline_analyses {
  return [ {
    -logic_name => 'ScheduleSpecies',
    -module     => 'Bio::EnsEMBL::Production::Pipeline::FASTA::ReuseSpeciesFactory',
    -parameters => {

    },
    -flow_into => {
      2 => ['DumpRDF']
    }
  },
  {
    -logic_name => 'DumpRDF';
    -module => 'Bio::EnsEMBL::RDF::Pipeline::Process::RDFDump',
    -parameters => {
      dump_location => '#dump_location#',
      xref => '#xref#',
    },
    -analysis_capacity => 6
  }];
}

# Optionally enable auto-variable passing to Hive.
# sub hive_meta_table {
#   my ($self) = @_;
#   return {
#     %{$self->SUPER::hive_meta_table},
#     hive_use_param_stack  => 1,
#   };
# }


1;