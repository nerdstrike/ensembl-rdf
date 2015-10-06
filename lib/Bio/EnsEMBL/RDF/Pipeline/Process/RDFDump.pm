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

=head1 NAME

    RDFDump - Hive Process to start with a species name and produce triples

=head1 DESCRIPTION

=cut

package Bio::EnsEMBL::RDF::Process::RDFDump;

use strict;

use parent ('Bio::EnsEMBL::RDF::Pipeline::Base');
use Bio::EnsEMBL::RDF::EnsemblToTripleConverter;

sub fetch_input {
    my $self = shift;
    $self->param_required('species');   # just make sure it has been passed
    $self->param_required('config_file');
    $self->param_required('release');
}


sub run {
    my $self = shift;
    my $species = $self->param('species');
    my $config_file = $self->param('config_file'); # config required for mapping Ensembl things to RDF (xref_LOD_mapping.json)
    my $path = $self->get_dir("$species.rdf");
    
    my $dba = $self->get_DBAdaptor;
    my $ontology_adaptor = $dba->get_OntologyAdaptor;
    my $meta_adaptor = $dba->get_MetaContainer;
    my $release = $self->param('release');

    my $triple_converter = Bio::EnsEMBL::RDF::EnsemblToTripleConverter->new($ontology_adaptor, $meta_adaptor, $species, undef, $release, $config_file);
    $triple_converter->write_to_file($path);

    $triple_converter->print_namespaces;
    $triple_converter->print_species_info;


    my $is_human;
    $is_human = 1 if $species eq 'homo_sapiens';
    my $slices = $self->get_Slices(undef,$is_human); # see Production::Pipeline::Base;
    $triple_converter->print_seq_regions($slices);
}


sub write_output {  # store and dataflow
    my $self = shift;
}




1;