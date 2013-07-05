package C3.Geoentity
{
	import C3.Object3DContainer;
	import C3.MD5.MD5Joint;
	import C3.MD5.MeshData;
	import C3.Material.IMaterial;

	public class MeshGeoentity extends Object3DContainer
	{
		public function MeshGeoentity(name : String, mat : IMaterial)
		{
			super(name,mat);
		}
		
		public function get meshDatas() : Vector.<MeshData>
		{
			throw new Error("这货需要重写");
		}
		
		public function get joints() : Vector.<MD5Joint>
		{
			throw new Error("这货需要重写");
		}
		
		public function get useCPU() : Boolean
		{
			throw new Error("这货需要重写");
		}
		
		public function get maxJoints() : uint
		{
			throw new Error("这货需要重写");
		}
	}
}