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

    EnsemblToTripleConverter - Module to help convert Ensembl data to RDF turtle

=head1 SYNOPSIS

  my $converter = Bio::EnsEMBL::RDF::EnsemblToTripleConverter->new($species,$file_handle);
  $converter->write_to_file('/direct/path/thing.rdf');
  $converter->print_namespaces;
  $converter->print_species_info;


=head1 DESCRIPTION

    Module to provide an API for turning Ensembl features and such into triples
    It relies on the RDFlib Bio::EnsEMB::RDF::RDFlib to provide common functions

=cut

package Bio::EnsEMBL::RDF::EnsemblToTripleConverter;

use Modern::Perl;
use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::RDF::RDFLib qw(:all);
use IO::File;

# species, filehandle
sub new {
  my($caller,@args) = @_;
  my $species = shift @args;
  my $fh = shift @args;
  # Requires Registry to be already connected up
  return bless ( {
    ontoa => Bio::EnsEMBL::Registry->get_adaptor( 'Multi', 'Ontology', 'OntologyTerm' ),
    species => $species,
    fh => $fh,
  }, $class);
}

# getter/setter
sub species {
  my ($self,$species) = @_;
  if ($species) { 
    $self->{species} = $species;
  }
  return $self->{species};
}

sub filehandle {
  my ($self,$fh) = @_;
  if ($fh) {
    if ($self->{fh}) {$self->{fh}->close}
    $self->{fh} = $fh;
  }
  return $self->{fh};
}

sub write_to_file {
  my ($self,$path) = @_;
  my $fh = IO::File->new($path, 'w');
  $self->filehandle($fh);
}

# General header stuff
sub print_namespaces {
  my $self = shift;
  my $fh = $self->filehandle;
  print $fh name_spaces();
}

sub print_species_info {
  # create a map of taxon id to species name, we will create some triples for these at the end
  my $fh = $self->filehandle;
  my $meta = Bio::EnsEMBL::Registry->get_adaptor($self->species,'Core','MetaContainer');
  # get the taxon id for this species 
  my $taxon_id = $meta->get_taxonomy_id;
  my $scientific_name = $meta->get_scientific_name;
  my $common_name = $meta->get_common_name;

  # print out global triples about the organism  
  print $fh triple('taxon:'.$taxon_id, 'rdfs:subClassOf', 'obo:OBI_0100026');
  print $fh triple('taxon:'.$taxon_id, 'rdfs:label', q("$scientific_name"));
  print $fh triple('taxon:'.$taxon_id, 'skos:altLabel', q("$common_name"));
  print $fh triple('taxon:'.$taxon_id, 'dc:identifier', q("$taxon_id"));
}

# SO terms often required for dumping RDF

sub getSOOntologyId {
  my ($self,$term) = @_;
  if (exists $self->{ontology_cache{$term}}) {
    return $self->{ontology_cache{$term}};
  }

  my ($typeterm) = @{ $self->{ontoa}->fetch_all_by_name( $term, 'SO' ) };
    
  unless ($typeterm) {
    warn "Can't find SO term for $term\n";
    $self->{$ontology_cache{$term}} = undef; 
    return;
  }
    
  my $id = $typeterm->accession;
  $id =~ s/SO:/obo:SO_/;
  $self->{$ontology_cache{$term}} = $id;
  return $id;
}



1;