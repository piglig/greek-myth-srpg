"""Project-local godot-ai MCP client; does not modify global Codex settings."""
import asyncio, json, sys, shutil
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
async def main():
    params=StdioServerParameters(command=shutil.which('uvx') or str(__import__('pathlib').Path.home()/'.local/bin/uvx'), args=['--from','godot-ai==4.4.1','godot-ai','attach','--disable-telemetry'])
    async with stdio_client(params) as (reader,writer):
        async with ClientSession(reader,writer) as session:
            await session.initialize()
            result=await session.list_tools()
            if len(sys.argv)==1:
                print(json.dumps([{'name':t.name,'description':t.description,'schema':t.input_schema} for t in result.tools],ensure_ascii=False))
            else:
                response=await session.call_tool(sys.argv[1],json.loads(sys.argv[2]))
                print(response.model_dump_json())
asyncio.run(main())
