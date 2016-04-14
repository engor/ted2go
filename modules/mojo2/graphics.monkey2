
Namespace mojo2

Private

#Import "<sdl2.monkey2>"

Using mojo2.glutil
Using mojo2.math3d
Using mojo2.glslparser

Using lib.c
Using lib.stb
Using lib.gles20

Using std
Using std.stringio
Using std.filesystem

#Import "data/mojo2_font.png@/mojo2"
#Import "data/mojo2_program.glsl@/mojo2"
#Import "data/mojo2_fastshader.glsl@/mojo2"
#Import "data/mojo2_bumpshader.glsl@/mojo2"
#Import "data/mojo2_matteshader.glsl@/mojo2"
#Import "data/mojo2_shadowshader.glsl@/mojo2"
#Import "data/mojo2_lightmapshader.glsl@/mojo2"

Const VBO_USAGE:=GL_STREAM_DRAW
Const VBO_ORPHANING_ENABLED:=False'True

Global graphicsSeq:=1

Const MAX_LIGHTS:=4
Const BYTES_PER_VERTEX:=28

'can really be anything <64K (due to 16bit indices) but this keeps total VBO size<64K, and making it bigger doesn't seem to improve performance much.
Const MAX_VERTICES:=65536/BYTES_PER_VERTEX	

Const MAX_QUADS:=MAX_VERTICES/4
Const MAX_QUAD_INDICES:=MAX_QUADS*6
Const PRIM_VBO_SIZE:=MAX_VERTICES*BYTES_PER_VERTEX

Global tmpi:=New Int[16]
Global tmpf:=New Float[16]

Global tmpMat2d:=New Float[6]
Global tmpMat3d:=New Float[16]
Global tmpMat3d2:=New Float[16]

Global defaultFbo:Int

Global mainShader:String

Global fastShader:Shader
Global bumpShader:Shader
Global matteShader:Shader
Global shadowShader:Shader
Global lightMapShader:Shader

Global defaultFont:Font
Global defaultShader:Shader

Global freeOps:=New Stack<DrawOp>
Global nullOp:=New DrawOp

'shader params
Global rs_projMatrix:=Mat4New()
Global rs_modelViewMatrix:=Mat4New()
Global rs_modelViewProjMatrix:=Mat4New()
Global rs_clipPosScale:=New Float[]( 1.0,1.0,1.0,1.0 )
Global rs_globalColor:=New Float[]( 1.0,1.0,1.0,1.0 )
Global rs_numLights:Int
Global rs_fogColor:=New Float[]( 0.0,0.0,0.0,0.0 )
Global rs_ambientLight:=New Float[]( 0.0,0.0,0.0,1.0 )
Global rs_lightColors:=New Float[MAX_LIGHTS*4]
Global rs_lightVectors:=New Float[MAX_LIGHTS*4]
Global rs_shadowTexture:Texture
Global rs_program:GLProgram
Global rs_material:Material
Global rs_blend:Int=-1
Global rs_vbo:GLuint
Global rs_ibo:GLuint

Function IsPow2:Bool( sz:Int )
	Return (sz & (sz-1))=0
End

Class LightData
	Field type:Int=0
	Field color:=New Float[]( 1.0,1.0,1.0,1.0 )
	Field position:=New Float[]( 0.0,0.0,-10.0 )
	Field range:Float=10
	'
	Field vector:=New Float[]( 0.0,0.0,-10.0,1.0 )
	Field tvector:=New Float[4]
End

Global flipYMatrix:=Mat4New()

Global vbosSeq:Int

Function Error:Void( err:String )
	Print "Error:"+err
	exit_( -1 )
End

Function InitVbos:Void()
	If vbosSeq=graphicsSeq 
		BindVbos()
		Return
	Endif
	vbosSeq=graphicsSeq

'	Print "InitVbos()"

	glGenBuffers( 1,Varptr rs_vbo )
	glBindBuffer( GL_ARRAY_BUFFER,rs_vbo )
	glBufferData( GL_ARRAY_BUFFER,PRIM_VBO_SIZE,Null,VBO_USAGE )
	glEnableVertexAttribArray( 0 ) ; glVertexAttribPointer( 0,2,GL_FLOAT,False,BYTES_PER_VERTEX,Byte Ptr( 0 ) )
	glEnableVertexAttribArray( 1 ) ; glVertexAttribPointer( 1,2,GL_FLOAT,False,BYTES_PER_VERTEX,Byte Ptr( 8 ) )
	glEnableVertexAttribArray( 2 ) ; glVertexAttribPointer( 2,2,GL_FLOAT,False,BYTES_PER_VERTEX,Byte Ptr( 16 ) )
	glEnableVertexAttribArray( 3 ) ; glVertexAttribPointer( 3,4,GL_UNSIGNED_BYTE,True,BYTES_PER_VERTEX,Byte Ptr( 24 ) )

	glGenBuffers( 1,Varptr rs_ibo )
	glBindBuffer( GL_ELEMENT_ARRAY_BUFFER,rs_ibo )
	Local idxs:=New UShort[ MAX_QUAD_INDICES*4 ]
	For Local j:=0 Until 4
		Local k:=j*MAX_QUAD_INDICES
		For Local i:=0 Until MAX_QUADS
			idxs[i*6+k+0]=i*4+j+0
			idxs[i*6+k+1]=i*4+j+1
			idxs[i*6+k+2]=i*4+j+2
			idxs[i*6+k+3]=i*4+j+0
			idxs[i*6+k+4]=i*4+j+2
			idxs[i*6+k+5]=i*4+j+3
		Next
	Next
	glBufferData( GL_ELEMENT_ARRAY_BUFFER,idxs.Length*2,Varptr idxs[0],GL_STATIC_DRAW )
End

Function BindVbos:Void()

	glBindBuffer( GL_ARRAY_BUFFER,rs_vbo )
	glEnableVertexAttribArray( 0 ) ; glVertexAttribPointer( 0,2,GL_FLOAT,False,BYTES_PER_VERTEX,Byte Ptr( 0 ) )
	glEnableVertexAttribArray( 1 ) ; glVertexAttribPointer( 1,2,GL_FLOAT,False,BYTES_PER_VERTEX,Byte Ptr( 8 ) )
	glEnableVertexAttribArray( 2 ) ; glVertexAttribPointer( 2,2,GL_FLOAT,False,BYTES_PER_VERTEX,Byte Ptr( 16 ) )
	glEnableVertexAttribArray( 3 ) ; glVertexAttribPointer( 3,4,GL_UNSIGNED_BYTE,True,BYTES_PER_VERTEX,Byte Ptr( 24 ) )

	glBindBuffer( GL_ELEMENT_ARRAY_BUFFER,rs_ibo )
End

Global inited:Bool

Function InitMojo2:Void()
	If inited Return
	inited=True
	
	InitVbos()
	
	glGetIntegerv( GL_FRAMEBUFFER_BINDING,Varptr defaultFbo )
	
	mainShader=LoadString( "asset::mojo2/mojo2_program.glsl" )
	
	fastShader=New Shader( LoadString( "asset::mojo2/mojo2_fastshader.glsl" ) )
	bumpShader=New BumpShader( LoadString( "asset::mojo2/mojo2_bumpshader.glsl" ) )
	matteShader=New MatteShader( LoadString( "asset::mojo2/mojo2_matteshader.glsl" ) )
	shadowShader=New Shader( LoadString( "asset::mojo2/mojo2_shadowshader.glsl" ) )
	lightMapShader=New Shader( LoadString( "asset::mojo2/mojo2_lightmapshader.glsl" ) )
	defaultShader=bumpShader
	
	defaultFont=Font.Load( "asset::mojo2/mojo2_font.png",32,96,True )'9,13,1,0,7,13,32,96 )
	If Not defaultFont Mojo2Error( "Can't load default font" )
	
	flipYMatrix[5]=-1

End

Class RefCounted

	Method Retain:Void()
		If _refs<=0 Mojo2Error( "Internal error" )
		_refs+=1
	End
	
	Method Release:Void()
		If _refs<=0 Mojo2Error( "Internal error" )
		
		_refs-=1
		If _refs Return
		_refs=-1
		Destroy()
	End
	
	Method Destroy:Void() Abstract
	
Private

	Field _refs:=1
End

Function KludgePath:String( path:String )
'	If path.StartsWith( "." ) Or path.StartsWith( "/" ) Return path
'	Local i:=path.Find( ":/" )
'	If i<>-1 And path.Find("/")=i+1 Return path
	Return "asset::"+path
End

Public

Function CrashGraphics:Void()
	graphicsSeq+=1
End

'***** Texture *****

Class Texture Extends RefCounted

	'flags
	Const Filter:=1
	Const Mipmap:=2
	Const ClampS:=4
	Const ClampT:=8
	Const ClampST:=12
	Const RenderTarget:=16
	Const Managed:=256
	
	Method New( width:Int,height:Int,format:Int,flags:Int,data:Pixmap=Null )
	
		If format<>4 Mojo2Error( "Invalid texture format: "+format )

		'can't mipmap NPOT textures on gles20
		If Not IsPow2( width ) Or Not IsPow2( height ) flags&=~Mipmap
		
		_width=width
		_height=height
		_format=format
		_flags=flags
		_data=data
		
		If _flags & Managed
			_managed=New Pixmap( width,height,PixelFormat.RGBA32 )
			If _data
				_managed.Paste( _data,0,0 )
				_data=Null
			Else
				_managed.ClearARGB( $ffff00ff )
			Endif
		Endif
		
		Validate()
	End
	
	Method Destroy:Void() Override
		If _seq=graphicsSeq	
			If _glTexture glDeleteTextures( 1,Varptr _glTexture )
			If _glFramebuffer glDeleteFramebuffers( 1,Varptr _glFramebuffer )
		Endif
		_glTexture=0
		_glFramebuffer=0
	End
	
	Property Width:Int()
		Return _width
	End
	
	Property Height:Int()
		Return _height
	End
	
	Property Format:Int()
		Return _format
	End
	
	Property Flags:Int()
		Return _flags
	End
	
	Method SetData( x:Int,y:Int,pixmap:Pixmap )
	
		If _managed
			If pixmap<>_managed _managed.Paste( pixmap,x,y )
		Else If _data
			If pixmap<>_data Mojo2Error( "Texture is read only" )
		Endif
		
		glPushTexture2d( GLTexture )
		
		Local width:=pixmap.Width,height:=pixmap.Height
		
		If pixmap.Pitch=_width*4
		
			glTexSubImage2D( GL_TEXTURE_2D,0,x,y,width,height,GL_RGBA,GL_UNSIGNED_BYTE,pixmap.Data )
			
		Else
		
			For Local iy:=0 Until height
				glTexSubImage2D( GL_TEXTURE_2D,0,x,y+iy,width,1,GL_RGBA,GL_UNSIGNED_BYTE,pixmap.PixelPtr( 0,iy ) )
			Next
			
		Endif
		
		glFlush()
		
		glPopTexture2d()
		
	End
	
	Method UpdateMipmaps:Void()
		If Not (_flags & Mipmap) Return
		
		If _seq<>graphicsSeq
			Validate()
			Return
		Endif

		glPushTexture2d( GLTexture )

		glGenerateMipmap( GL_TEXTURE_2D )
		
		glPopTexture2d()
	End
	
	Property Loading:Bool()
		Return False
	End
	
	Property GLTexture:Int()
		Validate()
		Return _glTexture
	End
	
	Property GLFramebuffer:Int()
		Validate()
		Return _glFramebuffer
	End		
	
	Function TexturesLoading:Int()
		Return 0
	End
	
	Function Load:Texture( path:String,format:Int=4,flags:Int=Filter|Mipmap|ClampST )

		Local data:=Pixmap.Load( path,PixelFormat.RGBA32 )
		If Not data Return Null
		
		data.PremultiplyAlpha()
		
		Local tex:=New Texture( data.Width,data.Height,format,flags,data )
		
		Return tex
	End
	
	Function Color:Texture( color:Int )
		Local tex:=_colors[color]
		If tex Return tex
		Local pixmap:=New Pixmap( 1,1,PixelFormat.RGBA32 )
		pixmap.ClearARGB( color )
		tex=New Texture( 1,1,4,ClampST,pixmap )
		_colors[color]=tex
		Return tex
	End
	
	Function Black:Texture()
		If Not _black _black=Color( $ff000000 )
		Return _black
	End
	
	Function White:Texture()
		If Not _white _white=Color( $ffffffff )
		Return _white
	End
	
	Function Magenta:Texture()
		If Not _magenta _magenta=Color( $ffff00ff )
		Return _magenta
	End
	
	Function Flat:Texture()
		If Not _flat _flat=Color( $ff888888 )
		Return _flat
	End
	
	Private
	
	Field _seq:Int
	Field _width:Int
	Field _height:Int
	Field _format:Int
	Field _flags:Int
	Field _data:Pixmap
	Field _managed:Pixmap
	
	Field _glTexture:GLuint
	Field _glFramebuffer:GLuint
	
	Global _colors:=New IntMap<Texture>
	Global _black:Texture
	Global _white:Texture
	Global _magenta:Texture
	Global _flat:Texture
	
	Method Validate()

		If _seq=graphicsSeq Return
		
		InitMojo2()
		
		_seq=graphicsSeq
	
		glGenTextures( 1,Varptr _glTexture )
		
		glPushTexture2d( _glTexture )
		
		If _flags & Filter
			glTexParameteri( GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR )
		Else
			glTexParameteri( GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST )
		Endif
		
		If (_flags & Mipmap) And (_flags & Filter)
			glTexParameteri( GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR_MIPMAP_LINEAR )
		Else If _flags & Mipmap
			glTexParameteri( GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST_MIPMAP_NEAREST )
		Else If _flags & Filter
			glTexParameteri( GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR )
		Else
			glTexParameteri( GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST )
		Endif

		If _flags & ClampS glTexParameteri( GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE )
		If _flags & ClampT glTexParameteri( GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE )

		glTexImage2D( GL_TEXTURE_2D,0,GL_RGBA,_width,_height,0,GL_RGBA,GL_UNSIGNED_BYTE,Null )

		glPopTexture2d()
		
		If _flags & RenderTarget
		
			glGenFramebuffers( 1,Varptr _glFramebuffer )
			
			glPushFramebuffer( _glFramebuffer )
			
			glBindFramebuffer( GL_FRAMEBUFFER,_glFramebuffer )
			glFramebufferTexture2D( GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,_glTexture,0 )
			
			If glCheckFramebufferStatus( GL_FRAMEBUFFER )<>GL_FRAMEBUFFER_COMPLETE Mojo2Error( "Incomplete framebuffer" )
			
			glPopFramebuffer()
			
		Endif
		
		If _managed
		
			SetData( 0,0,_managed )
			UpdateMipmaps()
			
		Else If _data
		
			SetData( 0,0,_data )
			UpdateMipmaps()
		
		Endif
		
	End
	
End

'***** Shader ****

Private

Class GLUniform
	Field name:String
	Field location:Int
	Field size:Int
	Field type:Int
	
	Method New( name:String,location:Int,size:Int,type:Int )
		Self.name=name
		Self.location=location
		Self.size=size
		Self.type=type
	End
	
End

Class GLProgram
	Field program:Int
	'material uniforms
	Field matuniforms:GLUniform[]
	'hard coded uniform locations
	Field mvpMatrix:Int
	Field mvMatrix:Int
	Field clipPosScale:Int
	Field globalColor:Int
	Field ambientLight:Int
	Field fogColor:Int
	Field lightColors:Int
	Field lightVectors:Int
	Field shadowTexture:Int
	
	Method New( program:Int,matuniforms:GLUniform[] )
		Self.program=program
		Self.matuniforms=matuniforms
		mvpMatrix=glGetUniformLocation( program,"ModelViewProjectionMatrix" )
		mvMatrix=glGetUniformLocation( program,"ModelViewMatrix" )
		clipPosScale=glGetUniformLocation( program,"ClipPosScale" )
		globalColor=glGetUniformLocation( program,"GlobalColor" )
		fogColor=glGetUniformLocation( program,"FogColor" )
		ambientLight=glGetUniformLocation( program,"AmbientLight" )
		lightColors=glGetUniformLocation( program,"LightColors" )
		lightVectors=glGetUniformLocation( program,"LightVectors" )
		shadowTexture=glGetUniformLocation( program,"ShadowTexture" )
	End
	
	Method Bind:Void()
	
		glUseProgram( program )
		
		If mvpMatrix<>-1 glUniformMatrix4fv( mvpMatrix,1,False,Varptr rs_modelViewProjMatrix[0] )
		If mvMatrix<>-1 glUniformMatrix4fv( mvMatrix,1,False,Varptr rs_modelViewMatrix[0] )
		If clipPosScale<>-1 glUniform4fv( clipPosScale,1,Varptr rs_clipPosScale[0] )
		If globalColor<>-1 glUniform4fv( globalColor,1,Varptr rs_globalColor[0] )
		If fogColor<>-1 glUniform4fv( fogColor,1,Varptr rs_fogColor[0] )
		If ambientLight<>-1 glUniform4fv( ambientLight,1,Varptr rs_ambientLight[0] )
		If lightColors<>-1 glUniform4fv( lightColors,rs_numLights,Varptr rs_lightColors[0] )
		If lightVectors<>-1 glUniform4fv( lightVectors,rs_numLights,Varptr rs_lightVectors[0] )
		If shadowTexture<>-1 
			Local tex:=rs_shadowTexture
			If Not tex tex=Texture.White()
			glActiveTexture( GL_TEXTURE0+7 )
			glBindTexture( GL_TEXTURE_2D,tex.GLTexture )
			glActiveTexture( GL_TEXTURE0 )
			glUniform1i( shadowTexture,7 )
		End
	End
	
End

Public

Class Shader

	Method New( source:String )
		Build( source )
	End
	
	Property DefaultMaterial:Material()
		If Not _defaultMaterial _defaultMaterial=New Material( Self )
		Return _defaultMaterial
	End
	
	Function FastShader:Shader()
		Return fastShader
	End
	
	Function BumpShader:Shader()
		Return bumpShader
	End
	
	Function MatteShader:Shader()
		Return matteShader
	End
	
	Function ShadowShader:Shader()
		Return shadowShader
	End
	
	Function LightMapShader:Shader()
		Return lightMapShader
	End
	
	Function DefaultShader:Shader()
		Return defaultShader
	End
	
	Function SetDefaultShader:Void( shader:Shader )
		If Not shader shader=bumpShader
		defaultShader=shader
	End
	
	Protected
	
	Method Build:Void( source:String )
		_source=source
		Build()
	End
	
	Method OnInitMaterial:Void( material:Material ) Virtual
		material.SetTexture( "ColorTexture",Texture.White() )
	End
	
	Method OnLoadMaterial:Material( material:Material,path:String,texFlags:Int ) Virtual
		Local texture:=Texture.Load( path,4,texFlags )
		If Not texture Return Null
		material.SetTexture( "ColorTexture",texture )
		If texture texture.Release()
		Return material
	End
	
	Private
	
	Const MAX_FLAGS:=8
	
	Field _seq:Int
	Field _source:String
	
	Field _vsource:String
	Field _fsource:String
	Field _uniforms:=New StringMap<Bool>
	
	Field _glPrograms:=New GLProgram[MAX_LIGHTS+1]
	
	Field _defaultMaterial:Material
	
	Method Bind:Void()
			
		Local program:=GLProgram
		
		If program=rs_program Return

		rs_program=program
		rs_material=Null
		
		program.Bind()
	End
	
	Property GLProgram:GLProgram()
	
		If _seq<>graphicsSeq 
			_seq=graphicsSeq
			rs_program=Null
			Build()
		Endif
		
		Return _glPrograms[rs_numLights]
	End
	
	Method Build:GLProgram( numLights:Int )
	
		Local defs:=""
		defs+="#define NUM_LIGHTS "+numLights+"~n"
		
		Local vshader:=glCompile( GL_VERTEX_SHADER,defs+_vsource )
		Local fshader:=glCompile( GL_FRAGMENT_SHADER,defs+_fsource )
		
		Local program:=glCreateProgram()
		glAttachShader( program,vshader )
		glAttachShader( program,fshader )
		glDeleteShader( vshader )
		glDeleteShader( fshader )
		
		glBindAttribLocation( program,0,"Position" )
		glBindAttribLocation( program,1,"Texcoord0" )
		glBindAttribLocation( program,2,"Tangent" )
		glBindAttribLocation( program,3,"Color" )
		
		glLink( program )
		
		'enumerate program uniforms	
		Local matuniforms:=New Stack<GLUniform>
		
		Local n:Int
		glGetProgramiv( program,GL_ACTIVE_UNIFORMS,Varptr n )

		Local size:Int,type:UInt,length:Int,nameBuf:=New Byte[256]
		
		For Local i:=0 Until n
			glGetActiveUniform( program,i,nameBuf.Length,Varptr length,Varptr size,Varptr type,Cast<GLchar Ptr>( Varptr nameBuf[0] ) )
			Local name:=String.FromCString( nameBuf.Data )
			If _uniforms.Contains( name )
				Local location:=glGetUniformLocation( program,name )
				If location=-1 Continue  'IE fix...
				matuniforms.Push( New GLUniform( name,location,size,type ) )
			Endif
		Next
		
		Return New GLProgram( program,matuniforms.ToArray() )
	
	End
	
	Method Build:Void()

		InitMojo2()
		
		Local p:=New GlslParser( _source )
		
		Local vars:=New StringMap<Bool>
		
		While p.Toke
		
			If p.CParse( "uniform" )
				'uniform decl
				Local ty:=p.ParseType()
				Local id:=p.ParseIdent()
				p.Parse( ";" )
				_uniforms.Set( id,True )
'				Print "uniform "+ty+" "+id+";"
				Continue
			Endif
			
			Local id:=p.CParseIdent()
			If id
				If id.StartsWith( "gl_" )
					vars.Set( "B3D_"+id.ToUpper(),True )
				Else If id.StartsWith( "b3d_" ) 
					vars.Set( id.ToUpper(),True )
				Endif
				Continue
			Endif
			
			p.Bump()
		Wend
		
		Local vardefs:=""
		For Local tvar:=Eachin vars.Keys
			vardefs+="#define "+tvar+" 1~n"
		Next
		
'		Print "Vardefs:";Print vardefs
		
		Local source:=mainShader
		Local i0:=source.Find( "//@vertex" )
		If i0=-1 Mojo2Error( "Can't find //@vertex chunk" )
		Local i1:=source.Find( "//@fragment" )
		If i1=-1 Mojo2Error( "Can't find //@fragment chunk" )
		
		Local header:=vardefs+source.Slice( 0,i0 )
		_vsource=header+source.Slice( i0,i1 )
		_fsource=header+source.Slice( i1 ).Replace( "${SHADER}",_source )
		
		For Local numLights:=0 To MAX_LIGHTS
		
			_glPrograms[numLights]=Build( numLights )

			If numLights Or vars.Contains( "B3D_DIFFUSE" ) Or vars.Contains( "B3D_SPECULAR" ) Continue
			
			For Local i:=1 To MAX_LIGHTS
				_glPrograms[i]=_glPrograms[0]
			Next
			
			Exit
			
		Next
		
	End
	
End

Class BumpShader Extends Shader

	Method New( source:String )
		Super.New( source )
	End

	Protected
	
	Method OnInitMaterial:Void( material:Material ) Override
		material.SetTexture( "ColorTexture",Texture.White() )
		material.SetTexture( "SpecularTexture",Texture.Black() )
		material.SetTexture( "NormalTexture",Texture.Flat() )
		material.SetVector( "AmbientColor",New Float[]( 1.0,1.0,1.0,1.0 ) )
		material.SetScalar( "Roughness",1.0 )
	End
	
	Method OnLoadMaterial:Material( material:Material,path:String,texFlags:Int ) Override
	
		Local format:=4
	
		Local ext:=ExtractExt( path )
		If ext path=StripExt( path ) Else ext=".png"

		Local colorTex:=Texture.Load( path+ext,format,texFlags )
		If Not colorTex colorTex=Texture.Load( path+"_d"+ext,format,texFlags )
		If Not colorTex colorTex=Texture.Load( path+"_diff"+ext,format,texFlags )
		If Not colorTex colorTex=Texture.Load( path+"_diffuse"+ext,format,texFlags )
		
		Local specularTex:=Texture.Load( path+"_s"+ext,format,texFlags )
		If Not specularTex specularTex=Texture.Load( path+"_spec"+ext,format,texFlags )
		If Not specularTex specularTex=Texture.Load( path+"_specular"+ext,format,texFlags )
		If Not specularTex specularTex=Texture.Load( path+"_SPECULAR"+ext,format,texFlags )
		
		Local normalTex:=Texture.Load( path+"_n"+ext,format,texFlags )
		If Not normalTex normalTex=Texture.Load( path+"_norm"+ext,format,texFlags )
		If Not normalTex normalTex=Texture.Load( path+"_normal"+ext,format,texFlags )
		If Not normalTex normalTex=Texture.Load( path+"_NORMALS"+ext,format,texFlags )

		If Not colorTex And Not specularTex And Not normalTex Return Null

		material.SetTexture( "ColorTexture",colorTex )
		material.SetTexture( "SpecularTexture",specularTex )
		material.SetTexture( "NormalTexture",normalTex )
		
		If specularTex Or normalTex
			material.SetVector( "AmbientColor",New Float[]( 0.0,0.0,0.0,1.0 ) )
			material.SetScalar( "Roughness",.5 )
		Endif
		
		If colorTex colorTex.Release()
		If specularTex specularTex.Release()
		If normalTex normalTex.Release()
		
		Return material
	End
	
End	

Class MatteShader Extends Shader

	Method New( source:String )
		Super.New( source )
	End
	
	Protected
	
	Method OnInitMaterial:Void( material:Material ) Override
		material.SetTexture( "ColorTexture",Texture.White() )
		material.SetVector( "AmbientColor",New Float[]( 0.0,0.0,0.0,1.0 ) )
		material.SetScalar( "Roughness",1.0 )
	End
	
End

'***** Material *****

Class Material Extends RefCounted

	Method New( shader:Shader=Null )
		InitMojo2()
		
		If Not shader shader=defaultShader
		_shader=shader
		_shader.OnInitMaterial( Self )
		_inited=True
	End
	
	Method Discard:Void()
		Super.Release()
	End
	
	Method Destroy:Void() Override
		For Local tex:=Eachin _textures
			tex.Value.Release()
		Next
	End
	
	Property Shader:Shader()
		Return _shader
	End
	
	Property ColorTexture:Texture()
		Return _colorTexture
	End
	
	Property Width:Int()
		If _colorTexture Return _colorTexture._width
		Return 0
	End
	
	property Height:Int()
		If _colorTexture Return _colorTexture._height
		Return 0
	End
	
	Method SetScalar:Void( param:String,scalar:Float )
		If _inited And Not _scalars.Contains( param ) Return
		_scalars.Set( param,scalar )
	End
	
	Method GetScalar:Float( param:String,defValue:Float=1.0 )
		If Not _scalars.Contains( param ) Return defValue
		Return _scalars.Get( param )
	End
	
	Method SetVector:Void( param:String,vector:Float[] )
		If _inited And Not _vectors.Contains( param ) Return
		_vectors.Set( param,vector )
	End
	
	Method GetVector:Float[]( param:String,defValue:Float[]=New Float[]( 1.0,1.0,1.0,1.0 ) )
		If Not _vectors.Contains( param ) Return defValue
		Return _vectors.Get( param )
	End
	
	Method SetTexture:Void( param:String,texture:Texture )
		If Not texture Return
		If _inited And Not _textures.Contains( param ) Return
		
		Local old:=_textures.Get( param )
		texture.Retain()
		_textures.Set( param,texture )
		If old old.Release()
		
		If param="ColorTexture" _colorTexture=texture
	End
	
	Method GetTexture:Texture( param:String,defValue:Texture=Null )
		If Not _textures.Contains( param ) Return defValue
		Return _textures.Get( param )
	End
	
	Method Loading:Bool()
		Return False
	End
	
	Function Load:Material( path:String,texFlags:Int,shader:Shader )
	
		Local material:=New Material( shader )
		
		material=material.Shader.OnLoadMaterial( material,path,texFlags )
		
		Return material
	End
	
	Private
	
	Field _shader:Shader
	Field _colorTexture:Texture
	Field _scalars:=New StringMap<Float>
	Field _vectors:=New StringMap<Float[]>
	Field _textures:=New StringMap<Texture>
	Field _inited:Bool
	
	Method Bind:Bool()
	
		_shader.Bind()
		
		If rs_material=Self Return True
		
		rs_material=Self
	
		Local texid:=0
		
		For Local u:=Eachin rs_program.matuniforms
			Select u.type
			Case GL_FLOAT
				glUniform1f( u.location,GetScalar( u.name ) )
			Case GL_FLOAT_VEC4
				glUniform4fv( u.location,1,Varptr GetVector( u.name )[0] )
			Case GL_SAMPLER_2D
				Local tex:=GetTexture( u.name )
				If Not tex
					Print "No texture! "+u.name
				Endif
				If tex.Loading
					rs_material=Null 
					Exit
				Endif
				glActiveTexture( GL_TEXTURE0+texid )
				glBindTexture( GL_TEXTURE_2D,tex.GLTexture )
				glUniform1i( u.location,texid )
				texid+=1
			Default
				Mojo2Error( "Unsupported uniform type:"+u.type )
			End
		Next

		If texid glActiveTexture( GL_TEXTURE0 )
		
		Return rs_material=Self
	End
	
End

'***** ShaderCaster *****

Class ShadowCaster

	Method New()
	End

	Method New( verts:Float[],type:Int )
		_verts=verts
		_type=type
	End
	
	Method SetVertices:Void( vertices:Float[] )
		_verts=vertices
	End
	
	Property Vertices:Float[]()
		Return _verts
	End
	
	Method SetType:Void( type:Int )
		_type=type
	End
	
	Property Type:Int()
		Return _type
	End
	
	Private
	
	Field _verts:Float[]
	Field _type:Int
	
End

'***** Image *****

Class Image

	Const Filter:=Texture.Filter
	Const Mipmap:=Texture.Mipmap
	Const Managed:=Texture.Managed
	
	Method New( pixmap:Pixmap,xhandle:Float=.5,yhandle:Float=.5,flags:Int=Image.Filter )
		Local texture:=New Texture( pixmap.Width,pixmap.Height,4,flags|Texture.ClampST,pixmap )
		_material=New Material( fastShader )
		_material.SetTexture( "ColorTexture",texture )
		texture.Release()
		_width=pixmap.Width
		_height=pixmap.Height
		SetHandle( xhandle,yhandle )
	End
	
	Method New( width:Int,height:Int,xhandle:Float=.5,yhandle:Float=.5,flags:Int=Image.Filter )
		Local texture:=New Texture( width,height,4,flags|Texture.ClampST|Texture.RenderTarget )
		_material=New Material( fastShader )
		_material.SetTexture( "ColorTexture",texture )
		texture.Release()
		_width=width
		_height=height
		SetHandle( xhandle,yhandle )
	End
	
	Method New( image:Image,x:Int,y:Int,width:Int,height:Int,xhandle:Float=.5,yhandle:Float=.5 )
		_material=image._material
		_material.Retain()
		_x=image._x+x
		_y=image._y+y
		_width=width
		_height=height
		SetHandle( xhandle,yhandle )
	End
	
	Method New( material:Material,xhandle:Float=.5,yhandle:Float=.5 )
		Local texture:=material.ColorTexture
		If Not texture Mojo2Error( "Material has no ColorTexture" )
		_material=material
		_material.Retain()
		_width=_material.Width
		_height=_material.Height
		SetHandle( xhandle,yhandle )
	End

	Method New( material:Material,x:Int,y:Int,width:Int,height:Int,xhandle:Float=.5,yhandle:Float=.5 )
		Local texture:=material.ColorTexture
		If Not texture Mojo2Error( "Material has no ColorTexture" )
		_material=material
		_material.Retain()
		_x=x
		_y=y
		_width=width
		_height=height
		SetHandle( xhandle,yhandle )
	End

	Method Discard:Void()
		If _material _material.Release()
		_material=Null
	End
	
	Property Material:Material()
		Return _material
	End
	
	Property X0:Float()
		Return _x0
	End
	
	Property Y0:Float()
		Return _y0
	End
	
	Property X1:Float()
		Return _x1
	End
	
	Property Y1:Float()
		Return _y1
	End
	
	Property Width:Int()
		Return _width
	End
	
	Property Height:Int()
		Return _height
	End
	
	Property HandleX:Float()
		Return -_x0/(_x1-_x0)
	End
	
	Property HandleY:Float()
		Return -_y0/(_y1-_y0)
	End
	
'	Method WritePixels:Void( x:Int,y:Int,width:Int,height:Int,data:DataBuffer,dataOffset:Int=0,dataPitch:Int=0 )
'		_material.ColorTexture.WritePixels( x+_x,y+_y,width,height,data,dataOffset,dataPitch )
'	End
	
	Method SetHandle:Void( xhandle:Float,yhandle:Float )
		_x0=Float(_width)*-xhandle
		_x1=Float(_width)*(1-xhandle)
		_y0=Float(_height)*-yhandle
		_y1=Float(_height)*(1-yhandle)
		_s0=Float(_x)/Float(_material.Width)
		_t0=Float(_y)/Float(_material.Height)
		_s1=Float(_x+_width)/Float(_material.Width)
		_t1=Float(_y+_height)/Float(_material.Height)
	End
	
	Method SetShadowCaster:Void( shadowCaster:ShadowCaster )
		_caster=shadowCaster
	End
	
	Property ShadowCaster:ShadowCaster()
		Return _caster
	End
	
	Method Loading:Bool()
		Return _material.Loading()
	End
	
	Function ImagesLoading:Bool()
		Return Texture.TexturesLoading()>0
	End
	
	Function Load:Image( path:String,xhandle:Float=.5,yhandle:Float=.5,flags:Int=Image.Filter|Image.Mipmap,shader:Shader=Null )
	
		Local material:=mojo2.Material.Load( path,flags|Texture.ClampST,shader )
		If Not material Return Null
		
		Return New Image( material,xhandle,yhandle )
	End
	
	Function LoadFrames:Image[]( path:String,numFrames:Int,padded:Bool=False,xhandle:Float=.5,yhandle:Float=.5,flags:Int=Image.Filter|Image.Mipmap,shader:Shader=Null )
	
		Local material:=mojo2.Material.Load( path,flags|Texture.ClampST,shader )
		If Not material Return Null
		
		Local cellWidth:=material.Width/numFrames,cellHeight:=material.Height
		
		Local x:=0,width:=cellWidth
		If padded x+=1;width-=2
		
		Local frames:=New Image[numFrames]
		
		For Local i:=0 Until numFrames
			frames[i]=New Image( material,i*cellWidth+x,0,width,cellHeight,xhandle,yhandle )
		Next
		
		Return frames
	End
	
	Private
	
	Field _material:Material
	Field _x:Int,_y:Int,_width:Int,_height:Int
	Field _x0:Float=-1,_y0:Float=-1,_x1:Float=1,_y1:Float=1
	Field _s0:Float=0 ,_t0:Float=0 ,_s1:Float=1,_t1:Float=1

	Field _caster:ShadowCaster
	
'	Method SetFrame:Void( x0:Float,y0:Float,x1:Float,y1:Float,s0:Float,t0:Float,s1:Float,t1:Float )
'		_x0=x0;_y0=y0;_x1=x1;_y1=y1
'		_s0=s0;_t0=t0;_s1=s1;_t1=t1
'	End
	
End

'***** Font *****

Class Glyph
	Field image:Image
	Field gchar:Int
	Field x:Int
	Field y:Int
	Field width:Int
	Field height:Int
	Field xoffset:Float
	Field yoffset:Float
	Field advance:Float
	
	Method New( image:Image,gchar:Int,x:Int,y:Int,width:Int,height:Int,xoffset:Float,yoffset:Float,advance:Float )
		Self.image=image
		Self.gchar=gchar
		Self.x=x
		Self.y=y
		Self.width=width
		Self.height=height
		Self.xoffset=xoffset
		Self.yoffset=yoffset
		Self.advance=advance
	End
End

Class Font

	Method New( glyphs:Glyph[],firstChar:Int,height:Float )
		_glyphs=glyphs
		_firstChar=firstChar
		_height=height
	End

	Method GetGlyph:Glyph( gchar:Int )
		Local i:=gchar-_firstChar
		If i>=0 And i<_glyphs.Length Return _glyphs[i]
		Return Null
	End
	
	Method TextWidth:Float( text:String )
		Local w:=0.0
		For Local gchar:=Eachin text
			Local glyph:=GetGlyph( gchar )
			If Not glyph Continue
			w+=Ceil( glyph.advance )
		Next
		Return w
	End

	Method TextHeight:Float( text:String )
		Return _height
	End
	
	Property Height:Int()
		Return _height
	End
	
	Function LoadTTF:Font( path:String,height:Int,firstChar:Int,numChars:Int )
	
		#rem
		'scale height DPI...
		Local ddpi:Float,hdpi:Float,vdpi:Float
		If sdl2.SDL_GetDisplayDPI( 0,Varptr ddpi,Varptr hdpi,Varptr vdpi )=0
'			Print "vdpi="+vdpi

'			Local height0:=height
	
'			height=Ceil( height*Clamp( vdpi/96.0,1.0,4.0 )+.5 )
			height=Floor( height*Clamp( vdpi/72.0,1.0,4.0 )+.5 )
			
'			Print "height0="+height0+", height="+height
		Endif
		#end
		
		Local data:=DataBuffer.Load( path )
		If Not data Return Null
		
		'Get font info
		Local f:stbtt_fontinfo,fp:=Varptr f
		If Not stbtt_InitFont( fp,data.Data,0 ) Return Null
	
		Local ascenti:Int,descenti:Int,linegapi:Int
		stbtt_GetFontVMetrics( fp,Varptr ascenti,Varptr descenti,Varptr linegapi )
		
		Local scale:=stbtt_ScaleForPixelHeight( fp,height )
		Local ascent:=ascenti*scale,descent:=descenti*scale,linegap:=linegapi*scale
		
		Local fheight:=(ascenti-descenti+linegapi)*scale
		
		'Bake the chars		
		Local bakedChars:=New stbtt_bakedchar[numChars]
		Local pixmap:=New Pixmap( 512,512,PixelFormat.I8 )
		stbtt_BakeFontBitmap( data.Data,0,height,pixmap.Data,512,512,firstChar,numChars,Varptr( bakedChars[0] ) )

		pixmap=pixmap.Convert( PixelFormat.RGBA32 )
		For Local y:=0 Until 512
			For Local x:=0 Until 512
				Local p:=pixmap.GetPixelARGB( x,y )
				pixmap.SetPixelARGB( x,y,(p & $ff0000) Shl 8 | (p & $ffffff) )
			Next
		Next
		
		Local texture:=New Texture( 512,512,4,Texture.ClampST,pixmap )
		
		Local material:=New Material( fastShader )
		material.SetTexture( "ColorTexture",texture )
		
		Local image:=New Image( material )
		
		Local glyphs:=New Glyph[numChars]
		
		For Local i:=0 Until numChars
		
			Local x:=bakedChars[i].x0
			Local y:=bakedChars[i].y0
			Local w:=bakedChars[i].x1-x
			Local h:=bakedChars[i].y1-y
			Local xoffset:=bakedChars[i].xoff
			Local yoffset:=bakedChars[i].yoff+ascent
			Local advance:=bakedChars[i].xadvance
			
			glyphs[i]=New Glyph( image,firstChar+i,x,y,w,h,xoffset,yoffset,advance )
		Next
		
		Return New Font( glyphs,firstChar,fheight )
	End
	
	Function Load:Font( path:String,firstChar:Int,numChars:Int,padded:Bool )
	
		Local image:=Image.Load( path )
		If Not image Return Null
		
		Local cellWidth:=image.Width/numChars
		Local cellHeight:=image.Height
		
		Local glyphX:=0,glyphY:=0,glyphWidth:=cellWidth,glyphHeight:=cellHeight
		If padded glyphX+=1;glyphY+=1;glyphWidth-=2;glyphHeight-=2

		Local w:=image.Width/cellWidth
		Local h:=image.Height/cellHeight

		Local glyphs:=New Glyph[numChars]
		
		For Local i:=0 Until numChars
			Local y:=i/w
			Local x:=i-y*w
			Local glyph:=New Glyph( image,firstChar+i,x*cellWidth+glyphX,y*cellHeight+glyphY,glyphWidth,glyphHeight,0,0,glyphWidth )
			glyphs[i]=glyph
		Next
		
		Return New Font( glyphs,firstChar,glyphHeight )
	
	End
	
	Function Load:Font( path:String,cellWidth:Int,cellHeight:Int,firstChar:Int,numChars:Int,padded:Bool )
	
		Local image:=Image.Load( path )
		If Not image Return Null
		
		Local glyphX:=0,glyphY:=0,glyphWidth:=cellWidth,glyphHeight:=cellHeight
		If padded glyphX+=1;glyphY+=1;glyphWidth-=2;glyphHeight-=2

		Local w:=image.Width/cellWidth
		Local h:=image.Height/cellHeight

		Local glyphs:=New Glyph[numChars]
		
		For Local i:=0 Until numChars
			Local y:=i/w
			Local x:=i-y*w
			Local glyph:=New Glyph( image,firstChar+i,x*cellWidth+glyphX,y*cellHeight+glyphY,glyphWidth,glyphHeight,0,0,glyphWidth )
			glyphs[i]=glyph
		Next
		
		Return New Font( glyphs,firstChar,glyphHeight )
	
	End
	
	Function Load:Font( path:String,cellWidth:Int,cellHeight:Int,glyphX:Int,glyphY:Int,glyphWidth:Int,glyphHeight:Int,firstChar:Int,numChars:Int )

		Local image:=Image.Load( path )
		If Not image Return Null

		Local w:=image.Width/cellWidth
		Local h:=image.Height/cellHeight

		Local glyphs:=New Glyph[numChars]
		
		For Local i:=0 Until numChars
			Local y:=i/w
			Local x:=i-y*w
			Local glyph:=New Glyph( image,firstChar+i,x*cellWidth+glyphX,y*cellHeight+glyphY,glyphWidth,glyphHeight,0,0,glyphWidth )
			glyphs[i]=glyph
		Next
		
		Return New Font( glyphs,firstChar,glyphHeight )
	End
	
	Function Open:Font( path:String,height:Int )
	
		Local tag:=path+"@"+String( height )
		
		Local font:=_fontCache[tag]
		If Not font
			If _fontCache.Contains( tag ) Return Null
			font=LoadTTF( path,height,32,96 )
			_fontCache[tag]=font
			
		Endif
		
		Return font
	End
	
	Private
	
	Field _glyphs:Glyph[]
	Field _firstChar:Int
	Field _height:Float
	
	Global _fontCache:=New StringMap<Font>
End

'***** DrawList *****

Class DrawOp
	Field material:Material
	Field blend:Int
	Field order:Int
	Field count:Int
End

Class BlendMode
	Const Opaque:=0
	Const Alpha:=1
	Const Additive:=2
	Const Multiply:=3
	Const Multiply2:=4
End

Class DrawList

	Method New()
		InitMojo2()
		
		SetFont( Null )
		SetDefaultMaterial( fastShader.DefaultMaterial )
	End
	
	Method SetBlendMode:Void( blend:Int )
		_blend=blend
	End
	
	property BlendMode:Int()
		Return _blend
	End
	
	Method SetColor:Void( r:Float,g:Float,b:Float )
		_color[0]=r
		_color[1]=g
		_color[2]=b
		_pmcolor=Int(_alpha) Shl 24 | Int(_color[2]*_alpha) Shl 16 | Int(_color[1]*_alpha) Shl 8 | Int(_color[0]*_alpha)
	End
	
	Method SetColor:Void( r:Float,g:Float,b:Float,a:Float )
		_color[0]=r
		_color[1]=g
		_color[2]=b
		_color[3]=a
		_alpha=a*255
		_pmcolor=Int(_alpha) Shl 24 | Int(_color[2]*_alpha) Shl 16 | Int(_color[1]*_alpha) Shl 8 | Int(_color[0]*_alpha)
	End
	
	Method SetAlpha:Void( a:Float )
		_color[3]=a
		_alpha=a*255
		_pmcolor=Int(_alpha) Shl 24 | Int(_color[2]*_alpha) Shl 16 | Int(_color[1]*_alpha) Shl 8 | Int(_color[0]*_alpha)
	End
	
	Property Color:Float[]()
		Return New Float[]( _color[0],_color[1],_color[2],_color[3] )
	End
	
	Method GetColor:Void( color:Float[] )
		color[0]=_color[0]
		color[1]=_color[1]
		color[2]=_color[2]
		If color.Length>3 color[3]=_color[3]
	End
	
	Property Alpha:Float()
		Return _color[3]
	End
	
	Method ResetMatrix:Void()
		_ix=1;_iy=0
		_jx=0;_jy=1
		_tx=0;_ty=0
	End
	
	Method SetMatrix:Void( ix:Float,iy:Float,jx:Float,jy:Float,tx:Float,ty:Float )
		_ix=ix;_iy=iy
		_jx=jx;_jy=jy
		_tx=tx;_ty=ty
	End
	
	Method GetMatrix:Void( matrix:Float[] )
		matrix[0]=_ix
		matrix[1]=_iy
		matrix[2]=_jx
		matrix[3]=_jy
		matrix[4]=_tx
		matrix[5]=_ty
	End
	
	Method Transform:Void( ix:Float,iy:Float,jx:Float,jy:Float,tx:Float,ty:Float )
		Local ix2:=ix*_ix+iy*_jx,iy2:=ix*_iy+iy*_jy
		Local jx2:=jx*_ix+jy*_jx,jy2:=jx*_iy+jy*_jy
		Local tx2:=tx*_ix+ty*_jx+_tx,ty2:=tx*_iy+ty*_jy+_ty
		SetMatrix( ix2,iy2,jx2,jy2,tx2,ty2 )
	End

	Method Translate:Void( tx:Float,ty:Float )
		Transform( 1,0,0,1,tx,ty )
	End
	
	Method Rotate( rz:Float )
		Transform( Cos( rz ),-Sin( rz ),Sin( rz ),Cos( rz ),0,0 )
	End
	
	Method Scale:Void( sx:Float,sy:Float )
		Transform( sx,0,0,sy,0,0 )
	End
	
	Method TranslateRotate:Void( tx:Float,ty:Float,rz:Float )
		Translate( tx,ty )
		Rotate( rz )
	End
	
	Method RotateScale:Void( rz:Float,sx:Float,sy:Float )
		Rotate( rz )
		Scale( sx,sy )
	End
	
	Method TranslateScale:Void( tx:Float,ty:Float,sx:Float,sy:Float )
		Translate( tx,ty )
		Scale( sx,sy )
	End
	
	Method TranslateRotateScale:Void( tx:Float,ty:Float,rz:Float,sx:Float,sy:Float )
		Translate( tx,ty )
		Rotate( rz )
		Scale( sx,sy )
	End
	
	Method SetMatrixStackCapacity:Void( capacity:Int )
		_matStack=New Float[ capacity*6 ]
		_matSp=0
	End
	
	Method MatrixStackCapacity:Int()
		Return _matStack.Length/6
	End
	
	Method PushMatrix:Void()
		_matStack[_matSp+0]=_ix;_matStack[_matSp+1]=_iy
		_matStack[_matSp+2]=_jx;_matStack[_matSp+3]=_jy
		_matStack[_matSp+4]=_tx;_matStack[_matSp+5]=_ty
		_matSp+=6
		If _matSp>=_matStack.Length _matSp-=_matStack.Length
	End
	
	Method PopMatrix:Void()
		_matSp-=6
		If _matSp<0 _matSp+=_matStack.Length
		_ix=_matStack[_matSp+0];_iy=_matStack[_matSp+1]
		_jx=_matStack[_matSp+2];_jy=_matStack[_matSp+3]
		_tx=_matStack[_matSp+4];_ty=_matStack[_matSp+5]
	End
	
	Method SetFont:Void( font:Font )
		If Not font font=defaultFont
		_font=font
	End
	
	Property Font:Font()
		Return _font
	End
	
	Method SetDefaultMaterial:Void( material:Material )
		_defaultMaterial=material
	End
	
	Property DefaultMaterial:Material()
		Return _defaultMaterial
	End
	
	Method DrawPoint:Void( x0:Float,y0:Float,material:Material=Null,s0:Float=0,t0:Float=0 )
		BeginPrim( material,1 )
		PrimVert( x0+.5,y0+.5,s0,t0 )
	End
	
	Method DrawLine:Void( x0:Float,y0:Float,x1:Float,y1:Float,material:Material=Null,s0:Float=0,t0:Float=0,s1:Float=1,t1:Float=0 )
		BeginPrim( material,2 )
		PrimVert( x0+.5,y0+.5,s0,t0 )
		PrimVert( x1+.5,y1+.5,s1,t1 )
	End
	
	Method DrawTriangle:Void( x0:Float,y0:Float,x1:Float,y1:Float,x2:Float,y2:Float,material:Material=Null,s0:Float=.5,t0:Float=0,s1:Float=1,t1:Float=1,s2:Float=0,t2:Float=1 )
		BeginPrim( material,3 )
		PrimVert( x0,y0,s0,t0 )
		PrimVert( x1,y1,s1,t1 )
		PrimVert( x2,y2,s2,t2 )
	End
	
	Method DrawQuad:Void( x0:Float,y0:Float,x1:Float,y1:Float,x2:Float,y2:Float,x3:Float,y3:Float,material:Material=Null,s0:Float=.5,t0:Float=0,s1:Float=1,t1:Float=1,s2:Float=0,t2:Float=1 )
		BeginPrim( material,4 )
		PrimVert( x0,y0,s0,t0 )
		PrimVert( x1,y1,s1,t1 )
		PrimVert( x2,y2,s2,t2 )
		PrimVert( x3,y3,s2,t2 )
	End
	
	Method DrawOval:Void( x:Float,y:Float,width:Float,height:Float,material:Material=Null )
		Local xr:=width/2.0,yr:=height/2.0
		
		Local dx_x:=xr*_ix,dx_y:=xr*_iy,dy_x:=yr*_jx,dy_y:=yr*_jy
		Local dx:=Sqrt( dx_x*dx_x+dx_y*dx_y ),dy:=Sqrt( dy_x*dy_x+dy_y*dy_y )

		Local n:=Int( dx+dy )
		If n<12 
			n=12 
		Else If n>MAX_VERTICES
			n=MAX_VERTICES
		Else
			n&=~3
		Endif
		
		Local x0:=x+xr,y0:=y+yr
		
		BeginPrim( material,n )
		
		For Local i:=0 Until n
			Local th:=i*360.0/n
			Local px:=x0+Cos( th ) * xr
			Local py:=y0+Sin( th ) * yr
			PrimVert( px,py,0,0 )
		Next
	End
	
	Method DrawEllipse:Void( x:Float,y:Float,xr:Float,yr:Float,material:Material=Null )
		DrawOval( x-xr,y-yr,xr*2,yr*2,material )
	End
	
	Method DrawCircle:Void( x:Float,y:Float,r:Float,material:Material=Null )
		DrawOval( x-r,y-r,r*2,r*2,material )
	End
	
	Method DrawPoly:Void( vertices:Float[],material:Material=Null )
	
		Local n:=vertices.Length/2
		If n<3 Or n>MAX_VERTICES Return
	
		BeginPrim( material,n )

		For Local i:=0 Until n
			PrimVert( vertices[i*2],vertices[i*2+1],0,0 )
		Next
	End
	
	Method DrawPrimitives:Void( order:Int,count:Int,vertices:Float[],material:Material=Null )
	
		BeginPrims( material,order,count )
		Local p:=0
		For Local i:=0 Until count
			For Local j:=0 Until order
				PrimVert( vertices[p],vertices[p+1],0,0 )
				p+=2
			Next
		Next
	End
	
	Method DrawPrimitives:Void( order:Int,count:Int,vertices:Float[],texcoords:Float[],material:Material=Null )
	
		BeginPrims( material,order,count )
		Local p:=0
		For Local i:=0 Until count
			For Local j:=0 Until order
				PrimVert( vertices[p],vertices[p+1],texcoords[p],texcoords[p+1] )
				p+=2
			Next
		Next
	End
	
	Method DrawIndexedPrimitives:Void( order:Int,count:Int,vertices:Float[],indices:Int[],material:Material=Null )
	
		BeginPrims( material,order,count )
		Local p:=0
		For Local i:=0 Until count
			For Local j:=0 Until order
				Local k:=indices[p+j]*2
				PrimVert( vertices[k],vertices[k+1],0,0 )
			Next
			p+=order
		Next
	
	End
	
	Method DrawIndexedPrimitives:Void( order:Int,count:Int,vertices:Float[],texcoords:Float[],indices:Int[],material:Material=Null )
	
		BeginPrims( material,order,count )
		Local p:=0
		For Local i:=0 Until count
			For Local j:=0 Until order
				Local k:=indices[p+j]*2
				PrimVert( vertices[k],vertices[k+1],texcoords[k],texcoords[k+1] )
			Next
			p+=order
		Next
	
	End
	
	Method DrawRect:Void( x0:Float,y0:Float,width:Float,height:Float,material:Material=Null,s0:Float=0,t0:Float=0,s1:Float=1,t1:Float=1 )
		Local x1:=x0+width,y1:=y0+height
		BeginPrim( material,4 )
		PrimVert( x0,y0,s0,t0 )
		PrimVert( x1,y0,s1,t0 )
		PrimVert( x1,y1,s1,t1 )
		PrimVert( x0,y1,s0,t1 )
	End
	
	Method DrawRect:Void( x0:Float,y0:Float,width:Float,height:Float,image:Image )
		DrawRect( x0,y0,width,height,image._material,image._s0,image._t0,image._s1,image._t1 )
	End
	
	Method DrawRect:Void( x:Float,y:Float,image:Image,sourceX:Int,sourceY:Int,sourceWidth:Int,sourceHeight:Int )
		DrawRect( x,y,sourceWidth,sourceHeight,image,sourceX,sourceY,sourceWidth,sourceHeight )
	End
	
	Method DrawRect:Void( x0:Float,y0:Float,width:Float,height:Float,image:Image,sourceX:Int,sourceY:Int,sourceWidth:Int,sourceHeight:Int )
		Local material:=image._material
		Local s0:=Float(image._x+sourceX)/Float(material.Width)
		Local t0:=Float(image._y+sourceY)/Float(material.Height)
		Local s1:=Float(image._x+sourceX+sourceWidth)/Float(material.Width)
		Local t1:=Float(image._y+sourceY+sourceHeight)/Float(material.Height)
		DrawRect( x0,y0,width,height,material,s0,t0,s1,t1 )
	End
	
	'gradient rect - kinda hacky, but doesn't slow anything else down
	Method DrawGradientRect:Void( x0:Float,y0:Float,width:Float,height:Float,r0:Float,g0:Float,b0:Float,a0:Float,r1:Float,g1:Float,b1:Float,a1:Float,axis:Int )
	
		r0*=_color[0];g0*=_color[1];b0*=_color[2];a0*=_alpha
		r1*=_color[0];g1*=_color[1];b1*=_color[2];a1*=_alpha
		
		Local pm0:=Int( a0 ) Shl 24 | Int( b0*a0 ) Shl 16 | Int( g0*a0 ) Shl 8 | Int( r0*a0 )
		Local pm1:=Int( a1 ) Shl 24 | Int( b1*a0 ) Shl 16 | Int( g1*a0 ) Shl 8 | Int( r1*a0 )
		
		Local x1:=x0+width,y1:=y0+height,s0:=0.0,t0:=0.0,s1:=1.0,t1:=1.0
		
		BeginPrim( Null,4 )

		Local pmcolor:=_pmcolor
		
		Select axis
		Case 0	'left->right
			_pmcolor=pm0
			PrimVert( x0,y0,s0,t0 )
			_pmcolor=pm1
			PrimVert( x1,y0,s1,t0 )
			PrimVert( x1,y1,s1,t1 )
			_pmcolor=pm0
			PrimVert( x0,y1,s0,t1 )
		Default	'top->bottom
			_pmcolor=pm0
			PrimVert( x0,y0,s0,t0 )
			PrimVert( x1,y0,s1,t0 )
			_pmcolor=pm1
			PrimVert( x1,y1,s1,t1 )
			PrimVert( x0,y1,s0,t1 )
		End
		
		_pmcolor=pmcolor
	End
	
	Method DrawImage:Void( image:Image )
		BeginPrim( image._material,4 )
		PrimVert( image._x0,image._y0,image._s0,image._t0 )
		PrimVert( image._x1,image._y0,image._s1,image._t0 )
		PrimVert( image._x1,image._y1,image._s1,image._t1 )
		PrimVert( image._x0,image._y1,image._s0,image._t1 )
		If image._caster AddShadowCaster( image._caster )
	End
	
	Method DrawImage:Void( image:Image,tx:Float,ty:Float )
		PushMatrix()
		Translate( tx,ty )
		DrawImage( image )
		PopMatrix()
	End

	Method DrawImage:Void( image:Image,tx:Float,ty:Float,rz:Float )
		PushMatrix()
		TranslateRotate( tx,ty,rz )
		DrawImage( image )
		PopMatrix()
	End
	
	Method DrawImage:Void( image:Image,tx:Float,ty:Float,rz:Float,sx:Float,sy:Float )
		PushMatrix()
		TranslateRotateScale( tx,ty,rz,sx,sy )
		DrawImage( image )
		PopMatrix()
	End
	
	Method DrawText:Void( text:String,x:Float,y:Float,xhandle:Float=0,yhandle:Float=0 )
		x-=_font.TextWidth( text )*xhandle
		y-=_font.TextHeight( text )*yhandle
		x=Floor( x+.5 )
		y=Floor( y+.5 )
		For Local gchar:=Eachin text
			Local glyph:=_font.GetGlyph( gchar )
			If Not glyph Continue
			DrawRect( x+glyph.xoffset,y+glyph.yoffset,glyph.image,glyph.x,glyph.y,glyph.width,glyph.height )
			x+=Ceil( glyph.advance )
		Next
	End
	
	Method DrawShadow:Bool( lx:Float,ly:Float,x0:Float,y0:Float,x1:Float,y1:Float )
	
		Local ext:=1024
	
		Local dx:=x1-x0,dy:=y1-y0
		Local d0:=Sqrt( dx*dx+dy*dy )
		Local nx:=-dy/d0,ny:=dx/d0
		Local pd:=-(x0*nx+y0*ny)
		
		Local d:=lx*nx+ly*ny+pd
		If d<0 Return False

		Local x2:=x1-lx,y2:=y1-ly
		Local d2:=ext/Sqrt( x2*x2+y2*y2 )
		x2=lx+x2*ext;y2=ly+y2*ext
		
		Local x3:=x0-lx,y3:=y0-ly
		Local d3:=ext/Sqrt( x3*x3+y3*y3 )
		x3=lx+x3*ext;y3=ly+y3*ext
		
		Local x4:=(x2+x3)/2-lx,y4:=(y2+y3)/2-ly
		Local d4:=ext/Sqrt( x4*x4+y4*y4 )
		x4=lx+x4*ext;y4=ly+y4*ext
		
		DrawTriangle( x0,y0,x4,y4,x3,y3 )
		DrawTriangle( x0,y0,x1,y1,x4,y4 )
		DrawTriangle( x1,y1,x2,y2,x4,y4 )
		
		Return True
	End
	
	Method DrawShadows:Void( x0:Float,y0:Float,drawList:DrawList )
	
		Local lx:= x0 * _ix + y0 * _jx + _tx
		Local ly:= x0 * _iy + y0 * _jy + _ty

		Local verts:=drawList._casterVerts.Data,v0:=0
		
		For Local i:=0 Until drawList._casters.Length
		
			Local caster:=drawList._casters.Get( i )
			Local n:=caster._verts.Length
			
			Select caster._type
			Case 0	'closed loop
				Local x0:=verts[v0+n-2]
				Local y0:=verts[v0+n-1]
				For Local i:=0 Until n-1 Step 2
					Local x1:=verts[v0+i]
					Local y1:=verts[v0+i+1]
					DrawShadow( lx,ly,x0,y0,x1,y1 )
					x0=x1
					y0=y1
				Next
			Case 1	'open loop
			Case 2	'edge soup
			End
			
			v0+=n
		Next
		
	End
	
	Method AddShadowCaster:Void( caster:ShadowCaster )
		_casters.Push( caster )
		Local verts:=caster._verts
		For 	Local i:=0 Until verts.Length-1 Step 2
			Local x0:=verts[i]
			Local y0:=verts[i+1]
			_casterVerts.Push( x0*_ix+y0*_jx+_tx )
			_casterVerts.Push( x0*_iy+y0*_jy+_ty )
		Next
	End
	
	Method AddShadowCaster:Void( caster:ShadowCaster,tx:Float,ty:Float )
		PushMatrix()
		Translate( tx,ty )
		AddShadowCaster( caster )
		PopMatrix()
	End
	
	Method AddShadowCaster:Void( caster:ShadowCaster,tx:Float,ty:Float,rz:Float )
		PushMatrix()
		TranslateRotate( tx,ty,rz )
		AddShadowCaster( caster )
		PopMatrix()
	End
	
	Method AddShadowCaster:Void( caster:ShadowCaster,tx:Float,ty:Float,rz:Float,sx:Float,sy:Float )
		PushMatrix()
		TranslateRotateScale( tx,ty,rz,sx,sy )
		AddShadowCaster( caster )
		PopMatrix()
	End
	
	Property IsEmpty:Bool()
		Return _next=0
	End
	
	Method Compact:Void()
		If _data.Length=_next Return
		Local data:=New DataBuffer( _next )
		_data.CopyTo( data,0,0,_next )
		_data.Discard()
		_data=data
	End
	
	Method Render:Void( op:DrawOp,index:Int,count:Int )
	
		If Not op.material.Bind() Return
		
		If op.blend<>rs_blend
			rs_blend=op.blend
			Select rs_blend
			Case mojo2.BlendMode.Opaque
				glDisable( GL_BLEND )
			Case mojo2.BlendMode.Alpha
				glEnable( GL_BLEND )
				glBlendFunc( GL_ONE,GL_ONE_MINUS_SRC_ALPHA )
			Case mojo2.BlendMode.Additive
				glEnable( GL_BLEND )
				glBlendFunc( GL_ONE,GL_ONE )
			Case mojo2.BlendMode.Multiply
				glEnable( GL_BLEND )
				glBlendFunc( GL_DST_COLOR,GL_ONE_MINUS_SRC_ALPHA )
			Case mojo2.BlendMode.Multiply2
				glEnable( GL_BLEND )
				glBlendFunc( GL_DST_COLOR,GL_ZERO )
			End
		End
		
		Select op.order
		Case 1
			glDrawArrays( GL_POINTS,index,count )
		Case 2
			glDrawArrays( GL_LINES,index,count )
		Case 3
			glDrawArrays( GL_TRIANGLES,index,count )
		Case 4
			glDrawElements( GL_TRIANGLES,count/4*6,GL_UNSIGNED_SHORT,Void Ptr( (index/4*6 + (index&3)*MAX_QUAD_INDICES)*2 ) )
		Default
			Local j:=0
			While j<count
				glDrawArrays( GL_TRIANGLE_FAN,index+j,op.order )
				j+=op.order
			Wend
		End

	End
	
	Method Render:Void()

		If Not _next Return
		
		Local offset:=0,opid:=0,ops:=_ops.Data
		Local length:=_ops.Length
		
		While offset<_next
		
			Local size:=_next-offset,lastop:=length
			
			If size>PRIM_VBO_SIZE
			
				size=0
				lastop=opid
				While lastop<length
					Local op:=ops[lastop]
					Local n:=op.count*BYTES_PER_VERTEX
					If size+n>PRIM_VBO_SIZE Exit
					size+=n
					lastop+=1
				Wend
				
				If Not size
					Local op:=ops[opid]
					Local count:=op.count
					While count
						Local n:=count
						If n>MAX_VERTICES n=MAX_VERTICES/op.order*op.order
						Local size:=n*BYTES_PER_VERTEX
						
						If VBO_ORPHANING_ENABLED glBufferData( GL_ARRAY_BUFFER,PRIM_VBO_SIZE,Null,VBO_USAGE )
						glBufferSubData( GL_ARRAY_BUFFER,0,size,_data.Data+offset )
						
						Render( op,0,n )
						
						offset+=size
						count-=n
					Wend
					opid+=1
					Continue
				Endif
				
			Endif
			
			If VBO_ORPHANING_ENABLED glBufferData( GL_ARRAY_BUFFER,PRIM_VBO_SIZE,Null,VBO_USAGE )
			glBufferSubData( GL_ARRAY_BUFFER,0,size,_data.Data+offset )
			
			Local index:=0
			While opid<lastop
				Local op:=ops[opid]
				Render( op,index,op.count )
				index+=op.count
				opid+=1
			Wend
			offset+=size
			
		Wend
		
		glGetError()
		
	End
	
	Method Reset:Void()
		_next=0
		
		Local data:=_ops.Data
		For Local i:=0 Until _ops.Length
			data[i].material=Null
			freeOps.Push( data[i] )
		Next
		_ops.Clear()
		_op=nullOp
		
		_casters.Clear()
		_casterVerts.Clear()
	End
	
	Method Flush:Void() Virtual
		Render()
		Reset()
	End
	
	Protected

	Field _blend:=1
	Field _alpha:=255.0
	Field _color:=New Float[]( 1.0,1.0,1.0,1.0 )
	Field _pmcolor:Int=$ffffffff
	Field _ix:Float=1,_iy:Float
	Field _jx:Float,_jy:Float=1
	Field _tx:Float,_ty:Float
	Field _matStack:=New Float[64*6]
	Field _matSp:Int
	Field _font:Font
	Field _defaultMaterial:Material
	
	Private
	
	Field _data:DataBuffer=New DataBuffer( 4096 )
	Field _next:=0
	Field _op:=nullOp
	Field _ops:=New Stack<DrawOp>
	Field _casters:=New Stack<ShadowCaster>
	Field _casterVerts:=New FloatStack

	Method BeginPrim:Void( material:Material,order:Int ) Final
	
		If Not material material=_defaultMaterial
		
		If _next+order*BYTES_PER_VERTEX>_data.Length
'			Print "Resizing data"
			Local newsize:=Max( _data.Length+_data.Length/2,_next+order*BYTES_PER_VERTEX )
			Local data:=New DataBuffer( newsize )
			_data.CopyTo( data,0,0,_next )
			_data.Discard()
			_data=data
		Endif
	
		If material=_op.material And _blend=_op.blend And order=_op.order
			_op.count+=order
			Return
		Endif
		
		If freeOps.Length _op=freeOps.Pop() Else _op=New DrawOp
		
		_ops.Push( _op )
		_op.material=material
		_op.blend=_blend
		_op.order=order
		_op.count=order
	End
	
	Method BeginPrims:Void( material:Material,order:Int,count:Int ) Final
	
		If Not material material=_defaultMaterial
		
		count*=order
		
		If _next+count*BYTES_PER_VERTEX>_data.Length
'			Print "Resizing data"
			Local newsize:=Max( _data.Length+_data.Length/2,_next+count*BYTES_PER_VERTEX )
			Local data:=New DataBuffer( newsize )
			_data.CopyTo( data,0,0,_next )
			_data.Discard()
			_data=data
		Endif
	
		If material=_op.material And _blend=_op.blend And order=_op.order
			_op.count+=count
			Return
		Endif
		
		If freeOps.Length _op=freeOps.Pop() Else _op=New DrawOp
		
		_ops.Push( _op )
		_op.material=material
		_op.blend=_blend
		_op.order=order
		_op.count=count
	End
	
	Method PrimVert:Void( x0:Float,y0:Float,s0:Float,t0:Float ) Final
		_data.PokeFloat( _next+0, x0 * _ix + y0 * _jx + _tx )
		_data.PokeFloat( _next+4, x0 * _iy + y0 * _jy + _ty )
		_data.PokeFloat( _next+8, s0 )
		_data.PokeFloat( _next+12,t0 )
		_data.PokeFloat( _next+16,_ix )
		_data.PokeFloat( _next+20,_iy )
		_data.PokeInt  ( _next+24,_pmcolor )
		_next+=BYTES_PER_VERTEX
	End
	
End

'***** Canvas *****

Class Canvas Extends DrawList

	Const MaxLights:=MAX_LIGHTS
	
	Method New( target:Object )
		Init()
		SetRenderTarget( target )
		SetViewport( 0,0,_width,_height )
		SetProjection2d( 0,_width,0,_height )
	End
	
	Method New( width:Int,height:Int )
		Init()
		Resize( width,height )
		SetViewport( 0,0,_width,_height )
		SetProjection2d( 0,_width,0,_height )
	End
	
	Method Resize( width:Int,height:Int )
		_image=Null
		_texture=Null
		_width=width
		_height=height
		_twidth=_width
		_theight=_height
		_dirty=-1
	End

	Method SetRenderTarget:Void( target:Object )

		FlushPrims()
		
		If Cast<Image>( target )
		
			_image=Cast<Image>( target )
			_texture=_image.Material.ColorTexture
			If Not (_texture.Flags & Texture.RenderTarget) Mojo2Error( "Texture is not a render target texture" )
			_width=_image.Width
			_height=_image.Height
			_twidth=_texture.Width
			_theight=_texture.Height
			
		Else If Cast<Texture>( target )
		
			_image=Null
			_texture=Cast<Texture>( target )
			If Not (_texture.Flags & Texture.RenderTarget) Mojo2Error( "Texture is not a render target texture" )
			_width=_texture.Width
			_height=_texture.Height
			_twidth=_texture.Width
			_theight=_texture.Height
			
		Else
		
			Mojo2Error( "RenderTarget object must an Image, a Texture or Null" )
			
		Endif
		
		_dirty=-1
		
	End
	
	Property RenderTarget:Object()
		If _image Return _image
		Return _texture
	End
	
	Property Width:Int()
		Return _width
	End
	
	Property Height:Int()
		Return _height
	End
	
	Method SetColorMask:Void( r:Bool,g:Bool,b:Bool,a:Bool )
		FlushPrims()
		_colorMask[0]=r
		_colorMask[1]=g
		_colorMask[2]=b
		_colorMask[3]=a
		_dirty|=DIRTY_COLORMASK
	End
	
	Property ColorMask:Bool[]()
		Return _colorMask
	End
	
	Method SetViewport:Void( x:Int,y:Int,w:Int,h:Int )
		FlushPrims()
		_viewport[0]=x
		_viewport[1]=y
		_viewport[2]=w
		_viewport[3]=h
		_dirty|=DIRTY_VIEWPORT
	End
	
	Property Viewport:Int[]()
		Return _viewport
	End
	
	Method SetScissor:Void( x:Int,y:Int,w:Int,h:Int )
		FlushPrims()
		_scissor[0]=x
		_scissor[1]=y
		_scissor[2]=w
		_scissor[3]=h
		_dirty|=DIRTY_VIEWPORT
	End
	
	Property Scissor:Int[]()
		Return _scissor
	End
	
	Method SetProjectionMatrix:Void( projMatrix:Float[] )
		FlushPrims()
		If projMatrix
			Mat4Copy( projMatrix,_projMatrix )
		Else
			Mat4Init( _projMatrix )
		Endif
		_dirty|=DIRTY_SHADER
	End
	
	Method SetProjection2d:Void( left:Float,right:Float,top:Float,bottom:Float,znear:Float=-1,zfar:Float=1 )
		FlushPrims()
		Mat4Ortho( left,right,top,bottom,znear,zfar,_projMatrix )
		_dirty|=DIRTY_SHADER
	End
	
	Property ProjectionMatrix:Float[]()
		Return _projMatrix
	End
	
	Method SetViewMatrix:Void( viewMatrix:Float[] )
		FlushPrims()
		If viewMatrix
			Mat4Copy( viewMatrix,_viewMatrix )
		Else
			Mat4Init( _viewMatrix )
		End
		_dirty|=DIRTY_SHADER
	End
	
	Property ViewMatrix:Float[]()
		Return _viewMatrix
	End
	
	Method SetModelMatrix:Void( modelMatrix:Float[] )
		FlushPrims()
		If modelMatrix
			Mat4Copy( modelMatrix,_modelMatrix )
		Else
			Mat4Init( _modelMatrix )
		Endif
		_dirty|=DIRTY_SHADER
	End
	
	Property ModelMatrix:Float[]()
		Return _modelMatrix
	End

	Method SetAmbientLight:Void( r:Float,g:Float,b:Float,a:Float=1 )
		FlushPrims()
		_ambientLight[0]=r
		_ambientLight[1]=g
		_ambientLight[2]=b
		_ambientLight[3]=a
		_dirty|=DIRTY_SHADER
	End
	
	Property AmbientLight:Float[]()
		Return _ambientLight
	End
	
	Method SetFogColor:Void( r:Float,g:Float,b:Float,a:Float )
		FlushPrims()
		_fogColor[0]=r
		_fogColor[1]=g
		_fogColor[2]=b
		_fogColor[3]=a
		_dirty|=DIRTY_SHADER
	End
	
	Property FogColor:Float[]()
		Return _fogColor
	End
	
	Method SetLightType:Void( index:Int,type:Int )
		FlushPrims()
		Local light:=_lights[index]
		light.type=type
		_dirty|=DIRTY_SHADER
	End
	
	Method GetLightType:Int( index:Int )
		Return _lights[index].type
	End
	
	Method SetLightColor:Void( index:Int,r:Float,g:Float,b:Float,a:Float=1 )
		FlushPrims()
		Local light:=_lights[index]
		light.color[0]=r
		light.color[1]=g
		light.color[2]=b
		light.color[3]=a
		_dirty|=DIRTY_SHADER
	End
	
	Method GetLightColor:Float[]( index:Int )
		Return _lights[index].color
	End
	
	Method SetLightPosition:Void( index:Int,x:Float,y:Float,z:Float )
		FlushPrims()
		Local light:=_lights[index]
		light.position[0]=x
		light.position[1]=y
		light.position[2]=z
		light.vector[0]=x
		light.vector[1]=y
		light.vector[2]=z
		_dirty|=DIRTY_SHADER
	End
	
	Method GetLightPosition:Float[]( index:Int )
		Return _lights[index].position
	End
	
	Method SetLightRange:Void( index:Int,range:Float )
		FlushPrims()
		Local light:=_lights[index]
		light.range=range
		_dirty|=DIRTY_SHADER
	End
	
	Method GetLightRange:Float( index:Int )
		Return _lights[index].range
	End
	
	Method SetShadowMap:Void( image:Image )
		FlushPrims()
		_shadowMap=image
		_dirty|=DIRTY_SHADER
	End
	
	Property ShadowMap:Image()
		Return _shadowMap
	End
	
	Method SetLineWidth:Void( lineWidth:Float )
		FlushPrims()
		_lineWidth=lineWidth
		_dirty|=DIRTY_LINEWIDTH
	End
	
	Property LineWidth:Float()
		Return _lineWidth
	End
	
	Method Clear:Void( r:Float=0,g:Float=0,b:Float=0,a:Float=1 )
		FlushPrims()
		Validate()
		If _clsScissor
			glEnable( GL_SCISSOR_TEST )
			glScissor( _vpx,_vpy,_vpw,_vph )
		Endif
		glClearColor( r,g,b,a )
		glClear( GL_COLOR_BUFFER_BIT )
		If _clsScissor glDisable( GL_SCISSOR_TEST )
	End
	
	Method ReadPixels:Void( x:Int,y:Int,width:Int,height:Int,data:DataBuffer,dataOffset:Int=0,dataPitch:Int=0 )
	
		FlushPrims()
		
		If Not dataPitch Or dataPitch=width*4
			glReadPixels( x,y,width,height,GL_RGBA,GL_UNSIGNED_BYTE,data.Data+dataOffset )
		Else
			For Local iy:=0 Until height
				glReadPixels( x,y+iy,width,1,GL_RGBA,GL_UNSIGNED_BYTE,data.Data+dataOffset+dataPitch*iy )
			Next
		Endif

	End

	Method RenderDrawList:Void( drawbuf:DrawList )
	
		Local fast:=_ix=1 And _iy=0 And _jx=0 And _jy=1 And _tx=0 And _ty=0 And _color[0]=1 And _color[1]=1 And _color[2]=1 And _color[3]=1
		
		If fast
			FlushPrims()
			Validate()
			drawbuf.Render()
			Return
		Endif
		
		tmpMat3d[0]=_ix
		tmpMat3d[1]=_iy
		tmpMat3d[4]=_jx
		tmpMat3d[5]=_jy
		tmpMat3d[12]=_tx
		tmpMat3d[13]=_ty
		tmpMat3d[10]=1
		tmpMat3d[15]=1
		
		Mat4Multiply( _modelMatrix,tmpMat3d,tmpMat3d2 )
		
		FlushPrims()
		
		Local tmp:=_modelMatrix
		_modelMatrix=tmpMat3d2
		rs_globalColor[0]=_color[0]*_color[3]
		rs_globalColor[1]=_color[1]*_color[3]
		rs_globalColor[2]=_color[2]*_color[3]
		rs_globalColor[3]=_color[3]
		_dirty|=DIRTY_SHADER
		
		Validate()
		drawbuf.Render()
		
		_modelMatrix=tmp
		rs_globalColor[0]=1
		rs_globalColor[1]=1
		rs_globalColor[2]=1
		rs_globalColor[3]=1
		_dirty|=DIRTY_SHADER
	End
	
	Method RenderDrawList:Void( drawList:DrawList,tx:Float,ty:Float,rz:Float=0,sx:Float=1,sy:Float=1 )
		Super.PushMatrix()
		Super.TranslateRotateScale( tx,ty,rz,sx,sy )
		RenderDrawList( drawList )
		Super.PopMatrix()
	End

	Method Flush:Void() Override
		FlushPrims()

		If Not _texture Return
#rem		
		
		If _texture._flags & Texture.Managed
			Validate()

			glDisable( GL_SCISSOR_TEST )
			glViewport( 0,0,_twidth,_theight )
			
			If _width=_twidth And _height=_theight
				glReadPixels 0,0,_twidth,_theight,GL_RGBA,GL_UNSIGNED_BYTE,DataBuffer( _texture._data )
			Else
				For Local y:=0 Until _height
					glReadPixels _image._x,_image._y+y,_width,1,GL_RGBA,GL_UNSIGNED_BYTE,DataBuffer( _texture._data ),(_image._y+y) * (_twidth*4) + (_image._x*4)
				Next
			Endif

			_dirty|=DIRTY_VIEWPORT
		Endif
#end

		_texture.UpdateMipmaps()
	End
	
	Global _tformInvProj:=New Float[16]
	Global _tformT:=New Float[]( 0.0,0.0,-1.0,1.0 )
	Global _tformP:=New Float[4]
	
	Method TransformCoords:Void( coords_in:Float[],coords_out:Float[],mode:Int=0 )
	
		Mat4Inverse( _projMatrix,_tformInvProj )

		Select mode
		Case 0
			_tformT[0]=(coords_in[0]-_viewport[0])/_viewport[2]*2-1
			_tformT[1]=(coords_in[1]-_viewport[1])/_viewport[3]*2-1
			Mat4Transform( _tformInvProj,_tformT,_tformP )
			_tformP[0]/=_tformP[3];_tformP[1]/=_tformP[3];_tformP[2]/=_tformP[3];_tformP[3]=1
			coords_out[0]=_tformP[0]
			coords_out[1]=_tformP[1]
			If coords_out.Length>2 coords_out[2]=_tformP[2]
		Default
			Mojo2Error( "Invalid TransformCoords mode" )
		End
	End
	
	Private

	Const DIRTY_RENDERTARGET:=1
	Const DIRTY_VIEWPORT:=2
	Const DIRTY_SHADER:=4
	Const DIRTY_LINEWIDTH:=8
	Const DIRTY_COLORMASK:=16
		
	Field _seq:Int
	Field _dirty:Int=-1
	Field _image:Image
	Field _texture:Texture	
	Field _width:Int
	Field _height:Int
	Field _twidth:Int
	Field _theight:Int
	Field _shadowMap:Image
	Field _colorMask:=New Bool[]( True,True,True,True )
	Field _viewport:=New Int[]( 0,0,640,480 )
	Field _scissor:=New Int[]( 0,0,100000,100000 )
	Field _vpx:Int,_vpy:Int,_vpw:Int,_vph:Int
	Field _scx:Int,_scy:Int,_scw:Int,_sch:Int
	Field _clsScissor:Bool
	Field _projMatrix:=Mat4New()
	Field _invProjMatrix:=Mat4New()
	Field _viewMatrix:=Mat4New()
	Field _modelMatrix:=Mat4New()
	Field _ambientLight:=New Float[]( 0.0,0.0,0.0,1.0 )
	Field _fogColor:=New Float[]( 0.0,0.0,0.0,0.0 )
	Field _lights:=New LightData[4]
	Field _lineWidth:Float=1

	Global _active:Canvas
	
	Method Init:Void()
		For Local i:=0 Until 4
			_lights[i]=New LightData
		Next
		_dirty=-1
	End

	Method FlushPrims:Void()
		If Super.IsEmpty Return
		Validate()
		Super.Flush()
	End
	
	Method Validate:Void()

		If _seq<>graphicsSeq
			_seq=graphicsSeq
			InitVbos()
			_dirty=-1
		Endif
	
		If _active=Self
			If Not _dirty Return
		Else
			If _active _active.Flush()
			_active=Self
			_dirty=-1
		Endif

'		_dirty=-1
		
		If _dirty & DIRTY_RENDERTARGET

			If _texture
				glBindFramebuffer( GL_FRAMEBUFFER,_texture.GLFramebuffer )
			Else
				glBindFramebuffer( GL_FRAMEBUFFER,defaultFbo )
			Endif
		End
		
		If _dirty & DIRTY_VIEWPORT
		
			_vpx=_viewport[0];_vpy=_viewport[1];_vpw=_viewport[2];_vph=_viewport[3]
			If _image
				_vpx+=_image._x
				_vpy+=_image._y
			Endif
			
			_scx=_scissor[0];_scy=_scissor[1];_scw=_scissor[2];_sch=_scissor[3]
			
			If _scx<0 _scx=0 Else If _scx>_vpw _scx=_vpw
			If _scw<0 _scw=0 Else If _scx+_scw>_vpw _scw=_vpw-_scx
			
			If _scy<0 _scy=0 Else If _scy>_vph _scy=_vph
			If _sch<0 _sch=0 Else If _scy+_sch>_vph _sch=_vph-_scy
			
			_scx+=_vpx;_scy+=_vpy
		
			If Not _texture
				_vpy=_theight-_vpy-_vph
				_scy=_theight-_scy-_sch
			Endif
			
			glViewport( _vpx,_vpy,_vpw,_vph )
			
			If _scx<>_vpx Or _scy<>_vpy Or _scw<>_vpw Or _sch<>_vph
				glEnable( GL_SCISSOR_TEST )
				glScissor( _scx,_scy,_scw,_sch )
				_clsScissor=False
			Else
				glDisable( GL_SCISSOR_TEST )
				_clsScissor=(_scx<>0 Or _scy<>0 Or _vpw<>_twidth Or _vph<>_theight)
			Endif
			
		Endif
		
		If _dirty & DIRTY_SHADER
		
			rs_program=Null
			
			If _texture
				rs_clipPosScale[1]=1
				Mat4Copy( _projMatrix,rs_projMatrix )
			Else
				rs_clipPosScale[1]=-1
				Mat4Multiply( flipYMatrix,_projMatrix,rs_projMatrix )
			Endif
			
			Mat4Multiply( _viewMatrix,_modelMatrix,rs_modelViewMatrix )
			Mat4Multiply( rs_projMatrix,rs_modelViewMatrix,rs_modelViewProjMatrix )
			Vec4Copy( _ambientLight,rs_ambientLight )
			Vec4Copy( _fogColor,rs_fogColor )
			
			rs_numLights=0
			For Local i:=0 Until MAX_LIGHTS

				Local light:=_lights[i]
				If Not light.type Continue
				
				Mat4Transform( _viewMatrix,light.vector,light.tvector )
				
				rs_lightColors[rs_numLights*4+0]=light.color[0]
				rs_lightColors[rs_numLights*4+1]=light.color[1]
				rs_lightColors[rs_numLights*4+2]=light.color[2]
				rs_lightColors[rs_numLights*4+3]=light.color[3]
				
				rs_lightVectors[rs_numLights*4+0]=light.tvector[0]
				rs_lightVectors[rs_numLights*4+1]=light.tvector[1]
				rs_lightVectors[rs_numLights*4+2]=light.tvector[2]
				rs_lightVectors[rs_numLights*4+3]=light.range

				rs_numLights+=1
			Next
			
			If _shadowMap
				rs_shadowTexture=_shadowMap._material._colorTexture
			Else 
				rs_shadowTexture=Null
			Endif
			
			rs_blend=-1

		End
		
		If _dirty & DIRTY_LINEWIDTH
			glLineWidth( _lineWidth )
		Endif
		
		If _dirty & DIRTY_COLORMASK
			glColorMask( _colorMask[0],_colorMask[1],_colorMask[2],_colorMask[3] )
		End
		
		_dirty=0
	End
	
End
