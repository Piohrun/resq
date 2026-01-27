.tst.desc["Test Loading"]{
 before{
  / Build base path as string from tstPath
  tstPathStr: .utl.pathToString .tst.tstPath;
  parts: "/" vs tstPathStr;
  `basePath mock "/" sv (-1 _ parts),enlist "nestedFiles";
  `pathList mock `foo`bar`baz! (basePath,"/foo"; basePath,"/bar"; basePath,"/baz");
  / Helper to get filename from a path string
  `getFilename mock {last "/" vs x};
 };
 should["recursively find all files matching an extension in a path"]{
  / suffixMatch returns list of string paths - extract filenames
  files: .tst.suffixMatch[".q";pathList[`foo]];
  filenames: asc getFilename each files;
  (asc ("a.q";"b.q";"c.q";"d.q";"d.q")) mustmatch filenames;

  filesK: .tst.suffixMatch[".k";pathList[`foo]];
  filenamesK: asc getFilename each filesK;
  (enlist "e.k") mustmatch filenamesK;
  };
 should["find all test files in a list of paths"]{
  files: .tst.findTests[value pathList];
  filenames: asc getFilename each files;
  (asc ("a.q";"b.q";"c.q";"d.q";"d.q";"f.q";"g.q")) mustmatch filenames;
  };
 should["return a q file given a q file"]{
  path: pathList[`foo],"/one/a.q"; / String path to known file
  result: .tst.findTests[path];
  / findTests should return a list with the single file
  (enlist path) mustmatch result;
  };
 };
