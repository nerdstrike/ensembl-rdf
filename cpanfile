requires 'Exporter::Auto';
requires 'JSON';
requires 'JSON::XS';
requires 'Getopt::Long';
requires 'Pod::Usage';
requires 'Bio::EnsEMBL::Registry';
requires 'Bio::EnsEMBL::DBSQL::DBAdaptor';
requires 'URI::Escape';
requires 'LWP::UserAgent';
requires 'Digest::MD5';

requires 'List::Compare';


requires 'Test::Exports';
# For testing
requires 'RDF::Trine';
requires 'RDF::Query';
requires 'Test::Deep';
# Also requires a working Ensembl installation for most operations.