package
{
	import com.adobe.utils.AGALMiniAssembler;
	import com.adobe.utils.PerspectiveMatrix3D;
	
	import flash.display3D.Context3DProgramType;
	import flash.display3D.Context3DTextureFormat;
	import flash.display3D.Context3DVertexBufferFormat;
	import flash.display3D.Program3D;
	import flash.display3D.textures.Texture;
	import flash.events.Event;
	import flash.events.KeyboardEvent;
	import flash.geom.Matrix3D;
	import flash.geom.Vector3D;

	/**
	 * 共享纹理测试
	 */
	[SWF(width = "512", height = "512", frameRate="60")]
	public class ShareTextureTest extends ContextBase
	{
		public function ShareTextureTest()
		{
			super();
		}
		
		protected override function onCreateContext(e:Event):void
		{
			super.onCreateContext(e);
			
			setup();
			m_viewMatrix.identity();
			m_viewMatrix.appendTranslation(0,0,20);
			m_viewMatrix.invert();
			
			this.addEventListener(Event.ENTER_FRAME, onEnter);
			stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
		}
		
		private function setup() : void
		{
			//创建512*512的阴影图
			m_depth = m_context.createTexture(
				Utils.nextPowerOfTwo(stage.stageWidth),
				Utils.nextPowerOfTwo(stage.stageHeight),
				Context3DTextureFormat.BGRA,
				true
			);
			
			texture = Utils.getTexture(textureData, m_context);
			
			m_showQuad = createQuad("show");
			m_leftQuad = createQuad("left");
			
			m_lightMatrix = new Matrix3D();
			m_lightProj = new PerspectiveMatrix3D();
			m_lightProj.perspectiveFieldOfViewRH(45,stage.stageWidth/stage.stageHeight, m_zNear, m_zNear);
			
			setupModelShader();
			setupDepthPassShader();
		}
		
		private function setupModelShader() : void
		{
			//创建模糊采样
			var blurStr : String;
			var blurNum : int = -m_blurSamples / 2;
			while(blurNum < m_blurSamples / 2){
				blurStr+=
					"tex ft3 ft2.xy fs0<2d,wrap,linear>\n"+
					"dp4 ft3 ft3 fc2\n"+
					"sub ft3 ft3 ft0\n"+
					"sge ft4 ft3 fc3.x\n"+
					"add ft5 ft5 ft4\n"+
					"add ft2.x ft2.x fc1.w\n";
				blurNum++;
			}
			
			/**
			 * v0 灯光空间顶点坐标
			 * v1 相机空间顶点坐标
			 * v2 法线
			 * v3 uv
			 */
			var modelVertexShader : AGALMiniAssembler = new AGALMiniAssembler();
			modelVertexShader.assemble(Context3DProgramType.VERTEX, 
				"m44 op va0 vc0\n"+
				"m44 v0 va0 vc4\n"+
				"mov v1 va0\n"+
				"mov v2 va1\n"+
				"mov v3 va2\n"+
				"mov v4 va3\n"+
				"mov v5 va4\n");
			
			var modelFragmentShader : AGALMiniAssembler = new AGALMiniAssembler();
			modelFragmentShader.assemble(Context3DProgramType.FRAGMENT,
				//前循环
				
				"div ft0 v0.z fc0.x\n"+
				"div ft2 v0.xy v0.ww\n"+
				"add ft2 ft2 fc0.y\n"+
				"mul ft2 ft2 fc0.z\n"+
				"sub ft2.y fc0.y ft2.y\n"+
				"mov ft1 fc0.w\n"+
				"mul ft1 ft1 fc1.w\n"+
				"add ft2.x ft2.x ft1\n"+
				
				//取出阴影图
				
				"tex ft3 ft2.xy fs0<2d,wrap,linear>\n" +
				
				//将像素转换成深度
				"dp4 ft3 ft3 fc2\n"+
				
				//当前顶点和灯光像素深度减去世界投影深度
				"sub ft3 ft3 ft0\n"+
				
				//如果 ft3 > fc3.x ? ft4 = 1 : ft4 = 0;
				//fc3.x 阴影比较值
				"sge ft4 ft3 fc3.x\n"+
				
				"mov ft5 ft4\n"+
				
				//将像素偏移到 2048 宽度的纹理上去
				"add ft2.x ft2.x fc1.w\n"+
				
				
				blurStr + 
				
				//后循环
				
				"div ft5 ft5 fc3.y\n"+
				"mul ft5 ft5 fc3.z\n"+
				"add ft5 ft5 fc3.z\n"+
				"sat ft5 ft5\n"+
				"mul ft5.xyz ft5.xyz fc1.xyz\n"+
				"mov ft0 ft5\n"+
				
				//漫反射光照
				
				"mov ft1 fc4\n"+
				"nrm ft1.xyz ft1\n"+
				"dp3 ft2 ft1 v2\n"+
				"sat ft2 ft2\n"+
				
				//镜面反射光照
				
				"add ft3 fc5.xyz, ft1.xyz\n"+
				"nrm ft3.xyz ft3\n"+
				"dp3 ft3 ft3 v2\n"+
				"pow ft3 ft3 fc5.w\n"+
				
				//光线合并 漫反射 + 镜面反射
				
				"add ft2 ft2 ft3\n"+
				
				//纹理颜色光照混合
				
				"mov ft4 v3\n"+
				"sub ft4.y fc1.x ft4.y\n"+
				"tex ft1 ft4 fs1<2d, wrap, linear>\n"+
				"mul ft1 ft1 ft2\n"+
				
				//输出 阴影透明度 * 纹理混合颜色
				"mul oc ft1 ft0\n");
				
			m_modelShaderProgram = m_context.createProgram();
			m_modelShaderProgram.upload(modelVertexShader.agalcode,modelFragmentShader.agalcode);
		}
		
		private function setupDepthPassShader() : void
		{
			var depthPassShaderProgran : AGALMiniAssembler = new AGALMiniAssembler();
			depthPassShaderProgran.assemble(Context3DProgramType.VERTEX,
				"m44 vt0 va0 vc0\n"+
				"mov op vt0\n"+
				"mov v0 vt0\n");
				
			/**
			 * v0 坐标在灯光投影的位置
			 */
			var depthPassFragmentProgram : AGALMiniAssembler = new AGALMiniAssembler();
			depthPassFragmentProgram.assemble(Context3DProgramType.FRAGMENT,
				
				//fc0 为zFar 这里作为最大深度 zFar/v0.z 求出 0-1 之前的深度范围
				"div ft0 v0.z fc0.x\n"+
				
				//将颜色编码为 32位浮点型数据存入RGBA
				"mul ft0 ft0 fc1\n"+
				
				//取出小数部分
				"frc ft0 ft0\n"+
				"mul ft1 ft0.yzww fc2\n"+
				"sub ft0 ft0 ft1\n"+
				"mov oc ft0\n");
			
			m_depthPassProgram = m_context.createProgram();
			m_depthPassProgram.upload(depthPassShaderProgran.agalcode,depthPassFragmentProgram.agalcode);
		}
		
		private function onEnter(e:Event) : void
		{
			if(m_depthPass){
				m_context.clear();
				m_context.setRenderToTexture(m_depth, true);
				
				m_lightMatrix.identity();
				m_lightMatrix.appendTranslation(0,0,0);
				
				m_context.setTextureAt(0,null);
				m_context.setTextureAt(1,null);
				m_context.setTextureAt(2,null);
				
				m_context.setVertexBufferAt(0,null);
				m_context.setVertexBufferAt(1,null);
				m_context.setVertexBufferAt(2,null);
				m_context.setVertexBufferAt(3,null);
				m_context.setVertexBufferAt(4,null);
				m_context.setVertexBufferAt(5,null);
				
				m_context.setProgram(m_depthPassProgram);
				
				var lightViewMatrix : Matrix3D = m_lightMatrix.clone();
				lightViewMatrix.invert();
				
				m_context.clear();
				m_lightProj.identity();
				m_lightProj.append(lightViewMatrix);
				m_lightProj.append(m_projMatrix);
				
				//vc0 灯光投影矩阵
				m_context.setProgramConstantsFromMatrix(Context3DProgramType.VERTEX, 0, m_lightProj, true);
				//fc0 m_zFar 最大深度?
				m_context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT,0, Vector.<Number>([m_zFar,1,1,1]));
				//???
				m_context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT,1, Vector.<Number>([1,256,65025,16581375]));
				//???
				m_context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT,2, Vector.<Number>([1/255,1/255,1/255,0]));
				
				//渲染quad
				m_context.setVertexBufferAt(0, m_showQuad.vertexBuffer,0,Context3DVertexBufferFormat.FLOAT_3);
//				m_context.setVertexBufferAt(1,m_showQuad.normalBuffer,0,Context3DVertexBufferFormat.FLOAT_3);
				m_context.drawTriangles(m_showQuad.indexBuffer);
				
				m_depthPass = false;
				m_context.present();
			}
			
			//正常绘制
			m_context.clear();
			m_context.setProgram(m_modelShaderProgram);
			
			var lightViewMatrix : Matrix3D = m_lightMatrix.clone();
			lightViewMatrix.invert();
			
			m_context.setTextureAt(0,m_depth);
			m_context.setTextureAt(1,texture);
			
			m_showQuad.transform.identity();
			m_finalMatrix.identity();
			m_finalMatrix.append(m_showQuad.transform);
			m_finalMatrix.append(m_viewMatrix);
			m_finalMatrix.append(m_projMatrix);
			
			m_context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, Vector.<Number>([m_zFar, 1, 0.5, -m_blurSamples / 2]));
			m_context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 1, Vector.<Number>([1, 1, 1, 1 / 2048]));
			m_context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 2, Vector.<Number>([1, 1 / 255, 1 / 65025, 1 / 16581375]));
			m_context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 3, Vector.<Number>([m_depthComparionThreshold,m_blurSamples,m_shadowAlpha,0]));
			//灯光位置
			m_context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 4, Vector.<Number>([0,0,0,1]));
			//相机位置
			m_context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 5, Vector.<Number>([0,0,0,m_glossiness]));
			//vc0 相机矩阵
			m_context.setProgramConstantsFromMatrix(Context3DProgramType.VERTEX, 0, m_finalMatrix, true);
			//vc4 灯光矩阵
			m_context.setProgramConstantsFromMatrix(Context3DProgramType.VERTEX, 4, m_lightProj, true);
			
			/**
			 * 渲染quad
			 *  "mov v1 va0\n"+
			 *	"mov v2 va1\n"+
			 *	"mov v3 va2\n"+
			 *	"mov v4 va3\n"+
			 *	"mov v5 va4\n");
			 * v0 灯光空间顶点坐标
			 * v1 相机空间顶点坐标
			 * v2 法线
			 * v3 uv
			 */
			m_context.setVertexBufferAt(0, m_showQuad.vertexBuffer,0,Context3DVertexBufferFormat.FLOAT_3);
			m_context.setVertexBufferAt(1,m_showQuad.uvBuffer,0,Context3DVertexBufferFormat.FLOAT_2);
			m_context.setVertexBufferAt(2,m_showQuad.normalBuffer,0,Context3DVertexBufferFormat.FLOAT_3);
			m_context.drawTriangles(m_showQuad.indexBuffer);
			
			m_context.present();
		}
		
		private function onKeyDown(e:KeyboardEvent) : void
		{
			m_depthPass = true;
		}
		
		private function renderScene() : void
		{
			m_context.clear(.5,.5,.5);
			m_context.setTextureAt(0, texture);
			m_context.setProgram(shader);
			
			m_leftQuad.transform.identity();
			m_leftQuad.transform.appendScale(2,2,2);
			m_leftQuad.transform.appendRotation(-60,Vector3D.X_AXIS);
			m_leftQuad.transform.appendTranslation(0,0,0);
			
			m_finalMatrix.identity();
			m_finalMatrix.append(m_leftQuad.transform);
			m_finalMatrix.append(m_viewMatrix);
			m_finalMatrix.append(m_projMatrix);
			
			m_context.setProgramConstantsFromMatrix(Context3DProgramType.VERTEX,0,m_finalMatrix,true);
			m_context.setVertexBufferAt(0,m_leftQuad.vertexBuffer,0,Context3DVertexBufferFormat.FLOAT_3);
			m_context.setVertexBufferAt(1,m_leftQuad.uvBuffer,0,Context3DVertexBufferFormat.FLOAT_2);
			m_context.drawTriangles(m_leftQuad.indexBuffer);
			
			m_context.setTextureAt(0,null);
		}
		
		private function renderShow() : void
		{
			m_context.setTextureAt(7, m_depth);
			m_context.setProgram(shadowShader);
			
			m_showQuad.transform.identity();
			m_showQuad.transform.appendScale(5,5,5);
			m_showQuad.transform.appendRotation(60,Vector3D.X_AXIS);
			m_showQuad.transform.appendTranslation(5,0,0);
			
			m_finalMatrix.identity();
			m_finalMatrix.append(m_showQuad.transform);
			m_finalMatrix.append(m_viewMatrix);
			m_finalMatrix.append(m_projMatrix);
			
			m_context.setProgramConstantsFromMatrix(Context3DProgramType.VERTEX,0,m_finalMatrix,true);
			m_context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, Vector.<Number>([60, 1, 0, 0]));
			m_context.setVertexBufferAt(0,m_showQuad.vertexBuffer,0,Context3DVertexBufferFormat.FLOAT_3);
			m_context.setVertexBufferAt(1,m_showQuad.uvBuffer,0,Context3DVertexBufferFormat.FLOAT_2);
			m_context.drawTriangles(m_showQuad.indexBuffer);
			
			m_context.setTextureAt(7, null);
		}
		
		private function renderDepth() : void
		{
			m_context.setRenderToTexture(m_depth,true);
		}
		
		private function createQuad(name : String) : QuadInfo
		{
			var vertexList : Vector.<Number> = new Vector.<Number>();
			vertexList.push(-1,1,0);
			vertexList.push(1,1,0);
			vertexList.push(1,-1,0);
			vertexList.push(-1,-1,0);
			
			var indexList : Vector.<uint> = new Vector.<uint>();
			indexList.push(0,1,2);
			indexList.push(0,2,3);
			
			var uvList : Vector.<Number> = new Vector.<Number>();
			uvList.push(0,0,1,0,1,1,0,1);
			
			var normalList : Vector.<Number> = new Vector.<Number>();
			normalList.push(0,0,0,0,0,0,0,0,0,0,0,0);
			
			var quad : QuadInfo = new QuadInfo();
			quad.name = name;
			
			quad.vertexBuffer = m_context.createVertexBuffer(4,3);
			quad.vertexBuffer.uploadFromVector(vertexList,0,4);
			
			quad.indexBuffer = m_context.createIndexBuffer(6);
			quad.indexBuffer.uploadFromVector(indexList,0,6);
			
			quad.uvBuffer = m_context.createVertexBuffer(4,2);
			quad.uvBuffer.uploadFromVector(uvList,0,4);
			
			quad.normalBuffer = m_context.createVertexBuffer(4,3);
			quad.normalBuffer.uploadFromVector(normalList,0,4);
			
			m_quadList.push(quad);
			
			return quad;
		}
		
		private function get shader() : Program3D
		{
			if(m_shader) return m_shader;
			
			var vertexProgram : AGALMiniAssembler = new AGALMiniAssembler();
			vertexProgram.assemble(Context3DProgramType.VERTEX,
				"m44 op, va0, vc0\n"+
				"mov v1, va1");
			
			var fragmentProgram : AGALMiniAssembler = new AGALMiniAssembler();
			fragmentProgram.assemble(Context3DProgramType.FRAGMENT,
				"tex ft0, v1, fs0<2d,linear,repeat>\n"+
				"mov oc, ft0\n");
			
			m_shader = m_context.createProgram();
			m_shader.upload(vertexProgram.agalcode,fragmentProgram.agalcode);
			
			return m_shader;
		}
		
		private function get shadowShader() : Program3D
		{
			if(m_depthShader) return m_depthShader;
			
			var vertexStr : String = "m44 vt0, va0, vc0\n"+
				"mov op, vt0\n"+
				"mov v0, va1\n"+
				"mov v1, vt0\n";
			
			var vertexProgram : AGALMiniAssembler = new AGALMiniAssembler();
			vertexProgram.assemble(Context3DProgramType.VERTEX,vertexStr);
			
			var fragmentStr : String = "tex ft0, v0, fs7<2d,linear,mipnone>\n"+
				"mov ft0.xyz, v1.zzz\n"+
				"div ft0.xyz, ft0.xyz, fc0.x\n"+
//				"sub ft0.xyz, fc0.yyy, ft0.xyz\n"+
				"mov oc, ft0\n";
			
			var fragtmentProgram : AGALMiniAssembler = new AGALMiniAssembler();
			fragtmentProgram.assemble(Context3DProgramType.FRAGMENT,fragmentStr);
			
			trace(fragmentStr);
			
			m_depthShader = m_context.createProgram();
			m_depthShader.upload(vertexProgram.agalcode,fragtmentProgram.agalcode);
			
			return m_depthShader;
		}
		
		private var m_quadList : Vector.<QuadInfo> = new Vector.<QuadInfo>();
		private var m_depth : Texture;
		private var m_shader : Program3D;
		private var m_depthShader : Program3D;
		private var m_lightProj : PerspectiveMatrix3D;
		private var m_lightMatrix : Matrix3D;
		private var m_depthPass : Boolean = true;
		private var m_depthComparionThreshold : Number = 0.00001;
		private var m_shadowAlpha : Number = .4;
		private var m_glossiness : Number = 12;
		
		private var m_blurSamples : int = 24;
		
		private var m_leftQuad : QuadInfo;
		private var m_showQuad : QuadInfo;
		
		private var m_modelShaderProgram : Program3D;
		private var m_depthPassProgram : Program3D;
		
		[Embed(source="../source/seber.jpg")]
		private var textureData : Class;
		private var texture : Texture;
	}
}
import flash.display3D.IndexBuffer3D;
import flash.display3D.VertexBuffer3D;
import flash.geom.Matrix3D;

class QuadInfo
{
	public var name : String;
	public var vertexBuffer : VertexBuffer3D;
	public var indexBuffer : IndexBuffer3D;
	public var uvBuffer : VertexBuffer3D;
	public var normalBuffer : VertexBuffer3D;
	public var transform : Matrix3D = new Matrix3D();
}