package C3.MD5
{
	/**
	 * 网格数据
	 */
	public class MeshData
	{
		public var md5_triangle : Vector.<MD5Triangle>;
		public var md5_weight : Vector.<MD5Weight>;
		public var md5_vertex : Vector.<MD5Vertex>;
		
		public var num_verts : int;
		public var num_tris : int;
		public var num_weights : int;
		
		public function MeshData()
		{
			md5_triangle = new Vector.<MD5Triangle>();
			md5_weight = new Vector.<MD5Weight>();
			md5_vertex = new Vector.<MD5Vertex>();
		}
		
		/**
		 * 获取UV
		 */
		public function getUv() : Vector.<Number>
		{
			var uvVec : Vector.<Number> = new Vector.<Number>();
			for each(var vert : MD5Vertex in md5_vertex)
			{
				uvVec.push(vert.uv_x, vert.uv_y);
			}
			
			return uvVec;
		}
		
		/**
		 * 获取顶点索引
		 */
		public function getIndex() : Vector.<uint>
		{
			var indexVec : Vector.<uint> = new Vector.<uint>();
			for each(var tri : MD5Triangle in md5_triangle)
			{
				indexVec = indexVec.concat(tri.indexVec);
			}
			
			return indexVec;
		}
	}
}