
#If __TARGET__="windows"

#Import "bin/wget.exe"

'to build resource.o when icon changes...
'
'windres resource.rc resource.o

#Import "logo/resource.o"

#Endif

'----------------------------

'#Import "<reflection>"

#Import "<std>"
#Import "<mojo>"
#Import "<mojox>"
#Import "<tinyxml2>"

#Import "mainwindow"
#Import "documentmanager"

#Import "actions/fileactions"
#Import "actions/editactions"
#Import "actions/buildactions"
#Import "actions/helpactions"
#Import "actions/findactions"
#Import "actions/viewactions"

#Import "finddialog"
#Import "debugview"
#Import "projectview"
#Import "helptree"
#Import "modulemanager"
#Import "ted2textview"
#Import "jsontreeview"
#Import "xmltreeview"
#Import "monkey2treeview"
#Import "gutterview"

#Import "plugin"
#Import "ted2document"
#Import "codedocument"
#Import "plaintextdocument"
#Import "imagedocument"
#Import "audiodocument"
#Import "jsondocument"
#Import "xmldocument"

#Import "eventfilters/textviewkeyeventfilter"

#Import "buildproduct"
#Import "editproductdialog"

#Import "mx2ccenv"

#Import "eventfilters/monkey2keyeventfilter"

#Import "syntax/keywords"
#Import "syntax/monkey2keywords"
#Import "syntax/highlighter"
#Import "syntax/monkey2highlighter"
#Import "syntax/cpphighlighter"
#Import "syntax/cppkeywords"
#Import "syntax/codeformatter"
#Import "syntax/monkey2formatter"

#Import "views/codetextview"
#Import "views/consoleext"
#Import "views/listviewext"
#Import "views/dialogext"
#Import "views/autocompleteview"
#Import "views/codetreeview"
#Import "views/treeviewext"
#Import "views/codegutterview"
#Import "views/toolbarext"
#Import "views/hint"
#Import "views/htmlviewext"
#Import "views/projectbrowser"
#Import "views/tabviewext"
#Import "views/statusbar"

#Import "parsers/parser"
#Import "parsers/monkey2parser"
#Import "parsers/codeitem"
#Import "parsers/parserplugin"

#Import "utils/jsonutils"
#Import "utils/utils"

#Import "test_files/parsertests"

#Import "themeimages"
#Import "findinfilesdialog"

#Import "prefs"
#Import "prefsdialog"
#Import "ProcessWrapper"



Namespace ted2go

Using std..
Using mojo..
Using mojox..
Using tinyxml2..


Global AppTitle:="Ted2Go v2.3"


Function Main()

#If __DESKTOP_TARGET__
	
	Local root:=AppDir()
	
	Local json:=JsonObject.Load( AppDir()+"state.json" )
	If json And json.Contains( "rootPath" )
		root=json["rootPath"].ToString()
	Endif
	
	ChangeDir( root )
	
	While GetFileType( "bin" )<>FileType.Directory Or GetFileType( "modules" )<>FileType.Directory

		If IsRootDir( CurrentDir() )
			
			Local ok:=Confirm( "Initializing","Error initializing - can't find working dir!~nDo you want to specify Monkey2 root folder now?" )
			If Not ok
				libc.exit_( 1 )
			End
			Local s:=requesters.RequestDir( "Choose Monkey2 folder",AppDir() )
			ChangeDir( s )
			Continue
		Endif
		
		ChangeDir( ExtractDir( CurrentDir() ) )
	Wend
	
	json=New JsonObject
	json["rootPath"]=New JsonString( CurrentDir() )
	json.Save( AppDir()+"state.json" )
	
#Endif
	
	'load ted2 state
	'
	Local jobj:=JsonObject.Load( "bin/ted2.state.json" )
	If Not jobj jobj=New JsonObject

	Prefs.LoadState( jobj )
	
	'initial theme
	'	
	If Not jobj.Contains( "theme" ) jobj["theme"]=New JsonString( "theme-classic-dark" )
	If Not jobj.Contains( "themeScale" ) jobj["themeScale"]=New JsonNumber( 1 )
	
	Local config:=New StringMap<String>
	
	config["initialTheme"]=jobj.GetString( "theme" )
	config["initialThemeScale"]=jobj.GetNumber( "themeScale" )
	
	'start the app!
	'	
	New AppInstance( config )
	
	'initial window state
	'
	Local flags:=WindowFlags.Resizable|WindowFlags.HighDPI

	Local rect:Recti
	
	If jobj.Contains( "windowRect" ) 
		rect=ToRecti( jobj["windowRect"] )
	Else
		Local w:=Min( 1024,App.DesktopSize.x-40 )
		Local h:=Min( 768,App.DesktopSize.y-64 )
		rect=New Recti( 0,0,w,h )
		flags|=WindowFlags.Center
	Endif

	New MainWindowInstance( AppTitle,rect,flags,jobj )
	
	' open docs from args
	Local args:=AppArgs()
	For Local i:=1 Until args.Length
		Local arg:=args[i]
		arg=arg.Replace( "\","/" )
		If GetFileType( arg ) = FileType.File
			MainWindow.OpenDocument( arg )
		Endif
	Next
	
	App.Run()
		
End


Function GetActionTextWithShortcut:String( action:Action )

	Return action.Text+" ("+action.HotKeyText+")"
End

