"""Write painted skinned triangle meshes with translation-only bind poses."""
import json
import struct
import numpy as np

def write_skin(out, name, nodes, root, origins, positions, normals, colors, texcoords, indices, weights):
    nodes = list(nodes)
    meshes, views, accessors = [], [], []
    blob = bytearray()
    def accessor(values, dtype="<f4", matrix=False):
        arr = np.asarray(values, dtype=dtype)
        while len(blob) % 4:
            blob.append(0)
        data = arr.tobytes()
        views.append(dict(buffer=0, byteOffset=len(blob), byteLength=len(data)))
        info = dict(bufferView=len(views)-1, componentType=5123 if dtype=="<u2" else 5126,
                    count=len(arr), type="MAT4" if matrix else f"VEC{arr.shape[1]}")
        if not matrix:
            info.update(min=arr.min(axis=0).tolist(), max=arr.max(axis=0).tolist())
        accessors.append(info)
        blob.extend(data)
        return len(accessors)-1


    attributes = dict(POSITION=accessor(positions), NORMAL=accessor(normals),
                      COLOR_0=accessor(colors), TEXCOORD_0=accessor(texcoords),
                      JOINTS_0=accessor(indices,"<u2"), WEIGHTS_0=accessor(weights))
    meshes.append(dict(name=name+"Skin", primitives=[dict(attributes=attributes, material=0)]))
    inverse_binds = []
    for origin in origins:
        m = np.eye(4)
        m[:3,3] = -origin
        inverse_binds.append(m.T.flatten())
    skin = dict(name=name+"Rig", skeleton=root, joints=list(range(len(nodes))),
                inverseBindMatrices=accessor(inverse_binds,matrix=True))
    mesh_node = len(nodes)
    nodes.append(dict(name=name+"Skin", mesh=0, skin=0))
    doc=dict(asset=dict(version="2.0"),scene=0,scenes=[dict(nodes=[root,mesh_node])],
             nodes=nodes,meshes=meshes,skins=[skin],buffers=[dict(byteLength=len(blob))],
             bufferViews=views,accessors=accessors,
             materials=[dict(doubleSided=True,pbrMetallicRoughness=dict(metallicFactor=.04,roughnessFactor=.82))])
    header=json.dumps(doc,separators=(',',':')).encode()
    header+=b' '*(-len(header)%4)
    out.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(header)+len(blob))+struct.pack('<I4s',len(header),b'JSON')+header+
                    struct.pack('<I4s',len(blob),b'BIN\x00')+blob)
