package Bio::EnsEMBL::RDF::RDFlib;

use Modern::Perl;
use Exporter::Easy ( OK => [ qw/u triple escape replace_whitespace taxonTriple /]);
use URI::Escape;

# common prefixes used
my %prefix = (
  ensembl => 'http://rdf.ebi.ac.uk/resource/ensembl/',
  ensemblvariation => 'http://rdf.ebi.ac.uk/terms/ensemblvariation/',
  transcript => 'http://rdf.ebi.ac.uk/resource/ensembl.transcript/',
  ensembl_variant => 'http://rdf.ebi.ac.uk/resource/ensembl.variant/',
  protein => 'http://rdf.ebi.ac.uk/resource/ensembl.protein/',
  exon => 'http://rdf.ebi.ac.uk/resource/ensembl.exon/',
  term => 'http://rdf.ebi.ac.uk/terms/ensembl/',
  rdfs => 'http://www.w3.org/2000/01/rdf-schema#',
  sio => 'http://semanticscience.org/resource/',
  dc => 'http://purl.org/dc/terms/',
  rdf => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
  faldo => 'http://biohackathon.org/resource/faldo#',
  obo => 'http://purl.obolibrary.org/obo/',
  skos => 'http://www.w3.org/2004/02/skos/core#',
  identifiers => 'http://identifiers.org/',
  taxon => 'http://identifiers.org/taxonomy/',
  oban => 'http://purl.org/oban/'
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
  $string =~ s/\s+/_/;
  return $string;
}


sub taxonTriple {
  my ($subject, $taxon_id) = @_;
  return triple($subject, 'obo:RO_0002162', 'taxon:'.$taxon_id);
}

# Put this somewhere else.
# SO terms often required for dumping RDF

sub getSOOntologyId {
  my $term = shift;
  if (exists $term2ontologyId{$term}) {
    return $term2ontologyId{$term};
  }

  my ($typeterm) = @{ $ontoa->fetch_all_by_name( $term, 'SO' ) };
    
  unless ($typeterm) {
    warn "Can't find SO term for $term\n";
    $term2ontologyId{$term} = undef; 
    return;
  }
    
  my $id = $typeterm->accession;
  $id=~s/SO:/obo:SO_/;
  $term2ontologyId{$term} = $id;
  return $id;    
}



1;