
Namespace ted2go


#Rem monkeydoc Add file extensions to open with CodeDocument.
All plugins with keywords should use this func inside of them OnCreate() callback.
#End
Function RegisterCodeExtensions(exts:String[])
	
	Local plugs := Plugin.PluginsOfType<CodeDocumentType>()
	If plugs = Null Return
	Local p := plugs[0]
	CodeDocumentTypeBridge.AddExtensions(p, exts)
	
End


Class CodeDocumentView Extends Ted2CodeTextView

	Method New( doc:CodeDocument )
	
		_doc=doc
		
		Document=_doc.TextDocument
		
		ContentView.Style.Border=New Recti( -4,-4,4,4 )
		
		AddView( New GutterView( Self ),"left" )

		'very important to set FileType for init
		'formatter, highlighter and keywords
		FileType = doc.FileType
		FilePath = doc.Path
		
		'AutoComplete
		If AutoComplete = Null Then AutoComplete = New AutocompleteDialog("")
		AutoComplete.OnChoosen += Lambda(text:String)
			If App.KeyView = Self
				SelectText(Cursor,Cursor-AutoComplete.Ident.Length)
				ReplaceText(text)
			Endif
		End
			
	End
	
	Property CharsToShowAutoComplete:Int()
		Return 2
	End
	
	Protected
	
	Method OnRenderContent( canvas:Canvas ) Override
	
		Local color:=canvas.Color
		
		If _doc._errors.Length
		
			canvas.Color=New Color( .5,0,0 )
			
			For Local err:=Eachin _doc._errors
				canvas.DrawRect( 0,err.line*LineHeight,Width,LineHeight )
			Next
			
		Endif
		
		If _doc._debugLine<>-1

			Local line:=_doc._debugLine
			If line<0 Or line>=Document.NumLines Return
			
			canvas.Color=New Color( 0,.5,0 )
			canvas.DrawRect( 0,line*LineHeight,Width,LineHeight )
			
		Endif
		
		canvas.Color=color
		
		Super.OnRenderContent( canvas )
	End
	
	Method OnKeyEvent( event:KeyEvent ) Override
		
		'ctrl+space - show autocomplete list
		If event.Type = EventType.KeyDown
			Select event.Key
			Case Key.Space
				If event.Modifiers & Modifier.Control
					Return
				Endif
			Case Key.Backspace
				If AutoComplete.IsOpened
					Local ident := IdentBeforeCursor()
					ident = ident.Slice(0,ident.Length-1)
					If ident.Length > 0
						ShowAutocomplete(ident)
					Else
						HideAutocomplete()
					Endif
				Endif
			End
			
		Elseif event.Type = EventType.KeyChar And event.Key = Key.Space And event.Modifiers & Modifier.Control
			Print "ctrl+space"
			ShowAutocomplete()
			Return
		Endif
		
		
		If event.Eaten Return
		'Print "super"
		Super.OnKeyEvent( event )
		
		'show autocomplete list after some typed chars
		If event.Type = EventType.KeyChar
			'preprocessor
			If event.Text = "#"
				ShowAutocomplete("#")
			Else
				Local ident := IdentBeforeCursor()
				If ident.Length >= CharsToShowAutoComplete
					ShowAutocomplete(ident)
				Else
					HideAutocomplete()
				Endif
			Endif
		Endif
		
	End
	
	Method OnContentMouseEvent( event:MouseEvent ) Override
		
		Select event.Type
			Case EventType.MouseClick
				HideAutocomplete()
		End
		
		Super.OnContentMouseEvent(event)
		
	End
	
	Method ShowAutocomplete(ident:String = "")
		'check ident
		If ident = "" Then ident = IdentBeforeCursor()
		
		'show
		Local line := Document.FindLine(Cursor)
		AutoComplete.Show(ident, FilePath, FileType, line)
		
		If AutoComplete.IsOpened
			Local frame := AutoComplete.Frame
			
			Local w := frame.Width
			Local h := frame.Height
			
			frame.Left = CursorRect.Left+100
			frame.Top = CursorRect.Top - Scroll.y
			frame.Right = frame.Left+w
			frame.Bottom = frame.Top+h
			
			AutoComplete.Frame = frame
		Endif
		
	End
	
	Method HideAutocomplete()
		AutoComplete.Hide()
	End
	
	
	Private
	
	Field _doc:CodeDocument

End


Class CodeDocument Extends Ted2Document

	Method New( path:String )
		Super.New( path )
	
		_doc=New TextDocument
		
		_doc.TextChanged=Lambda()
			Dirty=True
		End
		
		_doc.LinesModified=Lambda( first:Int,removed:Int,inserted:Int )
			Local put:=0
			For Local get:=0 Until _errors.Length
				Local err:=_errors[get]
				If err.line>=first
					If err.line<first+removed 
						err.removed=True
						Continue
					Endif
					err.line+=(inserted-removed)
				Endif
				_errors[put]=err
				put+=1
			Next
			_errors.Resize( put )
		End

		_view = New DockingView
		
		_treeView = New CodeTreeView
		_view.AddView( _treeView,"left",250,True )
		
		_codeView = New CodeDocumentView( Self )
		_view.ContentView = _codeView
				
	End
	
	Property TextDocument:TextDocument()
	
		Return _doc
	End
	
	Property DebugLine:Int()
	
		Return _debugLine
	
	Setter( debugLine:Int )
		If debugLine=_debugLine Return
		
		_debugLine=debugLine
		If _debugLine=-1 Return
		
		_codeView.GotoLine( _debugLine )
	End
	
	Property Errors:Stack<BuildError>()
	
		Return _errors
	End
	
	Private

	Field _doc:TextDocument

	Field _view:DockingView
	Field _codeView:CodeDocumentView
	Field _treeView:CodeTreeView
	
	Field _errors:=New Stack<BuildError>

	Field _debugLine:Int=-1
	
	Method OnLoad:Bool() Override
	
		Local text:=stringio.LoadString( Path )
		
		_doc.Text=text
		
		'code parser
		ParseSources()
		
		Return True
	End
	
	Method OnSave:Bool() Override
	
		Local text:=_doc.Text
		
		Local ok := stringio.SaveString( text,Path )
	
		'code parser - reparse
		ParseSources()
				
		Return ok
	End
	
	Method OnCreateView:View() Override
	
		Return _view
	End
	
	Method ParseSources()
		ParsersManager.Get(FileType).Parse(_doc.Text, Path)
		FillTreeView()
	End
	
	Method FillTreeView()
	
		Local stack := New Stack<TreeView.Node>
		Local parser := ParsersManager.Get(FileType)
		Local node := _treeView.RootNode
		_treeView.RootNodeVisible = False
		node.Expanded = True
		node.RemoveAllChildren()
		
		Local list := parser.ItemsMap[Path]
		If list = Null Return
		
		For Local i := Eachin list
			AddTreeItem(i, node)
		Next
		
		_treeView.NodeClicked = Lambda(node:TreeView.Node)
			Local codeNode := Cast<CodeTreeNode>(node)
			Local item := codeNode.CodeItem
			_codeView.GotoLine( item.ScopeStartLine )
		End
		
	End
	
	Method AddTreeItem(item:ICodeItem, node:TreeView.Node)
	
		Local n := New CodeTreeNode(item, node)
				
		If item.Children <> Null
			For Local i := Eachin item.Children
				AddTreeItem(i, n)
			End
		Endif
	End
	
End

Class CodeDocumentType Extends Ted2DocumentType

	Property Name:String() Override
		Return "CodeDocumentType"
	End
	
	Protected
	
	Method New()
		AddPlugin( Self )
		
		'Extensions=New String[]( ".monkey2",".cpp",".h",".hpp",".hxx",".c",".cxx",".m",".mm",".s",".asm",".html",".js",".css",".php",".md",".xml",".ini",".sh",".bat",".glsl")
	End
	
	Method OnCreateDocument:Ted2Document( path:String ) Override
	
		Return New CodeDocument( path )
	End
	
		
	Private
	
	Global _instance:=New CodeDocumentType
	
End


Private

Global AutoComplete:AutocompleteDialog


Class CodeDocumentTypeBridge Extends CodeDocumentType
	
	Function AddExtensions(inst:CodeDocumentType, exts:String[])
		inst.AddExtensions(exts)
	End
	
End