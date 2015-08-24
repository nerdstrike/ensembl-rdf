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

  RDFlib - library of functions for turning Ensembl data into RDF turtle

=head1 SYNOPSIS

  use Bio::EnsEMBL::RDF::RDFlib qw/u triple prefix/;
  print triple( u(prefix('ensembl').':'.$id) , 'rdf:label', 'insignificant text' );
  
  # More commonly you can use the shorthand to define namespaces
  print name_spaces;
  print triple('ensembl:ENSG001', 'rdf:label', 'inconsequential text');

=head1 DESCRIPTION

  A bunch of common shortcuts for formatting RDF for printing and supplying things like unique bnode IDs.

=cut

package Bio::EnsEMBL::RDF::RDFlib;

use Modern::Perl;
use Exporter::Auto;
use URI::Escape;

# common prefixes used
my %prefix = (
  ensembl     => 'http://rdf.ebi.ac.uk/resource/ensembl/',
  ensemblvariation => 'http://rdf.ebi.ac.uk/terms/ensemblvariation/',
  transcript => 'http://rdf.ebi.ac.uk/resource/ensembl.transcript/',
  ensembl_variant => 'http://rdf.ebi.ac.uk/resource/ensembl.variant/',
  protein     => 'http://rdf.ebi.ac.uk/resource/ensembl.protein/',
  exon        => 'http://rdf.ebi.ac.uk/resource/ensembl.exon/',
  term        => 'http://rdf.ebi.ac.uk/terms/ensembl/',
  rdfs        => 'http://www.w3.org/2000/01/rdf-schema#',
  sio         => 'http://semanticscience.org/resource/',
  dc          => 'http://purl.org/dc/terms/',
  rdf         => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
  faldo       => 'http://biohackathon.org/resource/faldo#',
  obo         => 'http://purl.obolibrary.org/obo/',
  skos        => 'http://www.w3.org/2004/02/skos/core#',
  identifiers => 'http://identifiers.org/',
  taxon       => 'http://identifiers.org/taxonomy/',
  ident_type  => 'http://idtype.identifiers.org/',
  oban        => 'http://purl.org/oban/',
  interpro    => "http://purl.uniprot.org/interpro/",
  scanprosite => "http://purl.uniprot.org/prosite/",
  prosite_patterns => "http://purl.uniprot.org/prosite/",
  prosite_profiles => "http://purl.uniprot.org/prosite/",
  pirsf       => "http://purl.uniprot.org/pirsf/",
  hamap       => "http://purl.uniprot.org/hamap/",
  prints      => "http://purl.uniprot.org/prints/",
  pfscan      => "http://purl.uniprot.org/profile/",
  gene3d      => "http://purl.uniprot.org/gene3d/",
  tigrfam     => "http://purl.uniprot.org/tigrfams/",
  smart       => "http://purl.uniprot.org/smart/",
  hmmpanther  => "http://purl.uniprot.org/panther/",
  panther     => "http://purl.uniprot.org/panther/",
  superfamily => "http://purl.uniprot.org/supfam/",
  pfam        => "http://purl.uniprot.org/pfam/",
  blastprodom => "http://purl.uniprot.org/prodom/",
  prodom      => "http://purl.uniprot.org/prodom/",
);

# Set of RDF-writing utility functions

# URI-ify
sub u {
  my $stuff= shift;
  return '<'.$stuff.'>';
}

sub triple {
    my ($subject,$predicate,$object) = @_;    
    return sprintf "%s %s %s .\n",$subject,$predicate,$object;
}

sub escape {
  my $string = shift;
  $string =~s/(["])/\\$1/g;
  return $string;
}

sub replace_whitespace {
  my $string = shift;
  $string =~ s/\s+/_/g;
  return $string;
}

sub taxon_triple {
  my ($subject, $taxon_id) = @_;
  return triple($subject, 'obo:RO_0002162', 'taxon:'.$taxon_id);
}

# prefix('faldo') etc.
sub prefix {
  my $key = shift;
  return $prefix{$key};
}

sub name_spaces {
  return join "\n",map { sprintf '@prefix %s: %s .',$_,u($prefix{$_}) } keys %prefix;  
}

# bnodes must only be unique within a single document, hence a single run of this module is sufficient for the state.
my $b_node_count = 0;
sub new_bnode {
  my $self = shift;
  $b_node_count++;
  return '_'.$b_node_count;
}

1;