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
use parent 'Bio::EnsEMBL::Hive::PipeConfig::EnsemblGeneric_conf';

sub default_options {
  my $self = shift;
  return {
    %{ $self->SUPER::default_options() },
    xref => 1,
    dump_location => '', # base path for all RDF output
    config_file => 'xref_LOD_mapping.json',
    pipeline_name => 'rdf_dump',
    registry => 'Reg', #/Users/ktaylor/ensembl/ensembl-rdf/lib/
    base_path => '/lustre/scratch109/ensembl/kt7/rdf/'
  }
}

sub pipeline_wide_parameters {
  my $self = shift;
  return {
    %{ $self->SUPER::pipeline_wide_parameters() },
    base_path => $self->o('base_path')
  }
}

sub pipeline_analyses {
  my $self = shift;
  return [ {
    -logic_name => 'ScheduleSpecies',
    -module     => 'Bio::EnsEMBL::Production::Pipeline::SpeciesFactory',
    -input_id => [{}], # required for automatic seeding
    -parameters => {

    },
    -flow_into => {
      2 => ['DumpRDF']
    }
  },
  {
    -logic_name => 'DumpRDF',
    -module => 'Bio::EnsEMBL::RDF::Pipeline::Process::RDFDump',
    -parameters => {
      dump_location => $self->o('dump_location'),
      xref => $self->o('xref'),
      release => $self->o('ensembl_release'),
      config_file => $self->o('config_file'),
      # species => $self->o('species'),
    },
    -analysis_capacity => 4,
	  -rc_name => 'dump'
  }];
}

sub beekeeper_extra_cmdline_options {
    my $self = shift;
    return "-reg_conf ".$self->o("registry");
}

# Optionally enable auto-variable passing to Hive.
# sub hive_meta_table {
#   my ($self) = @_;
#   return {
#     %{$self->SUPER::hive_meta_table},
#     hive_use_param_stack  => 1,
#   };
# }
sub resource_classes {
my $self = shift;
  return {
    'dump'      => { LSF => '-q normal -M8000 -R"select[mem>8000] rusage[mem=8000]"' },
  }
}

1;
