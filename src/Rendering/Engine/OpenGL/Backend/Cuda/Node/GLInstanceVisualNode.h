/**
 * Copyright 2017-2021 Xiaowei He
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#pragma once
#include <Node.h>

#include <Topology/TriangleSet.h>
#include "GraphicsObject/Shape.h"
#include "GraphicsObject/Material.h"
#include "GraphicsObject/Instance.h"


namespace dyno
{
	template<typename TDataType>
	class GLInstanceVisualNode : public Node
	{
		DECLARE_TCLASS(GLInstanceVisualNode, TDataType)
	public:
		typedef typename TDataType::Coord Coord;

		GLInstanceVisualNode();
		~GLInstanceVisualNode() override;

	public:
		std::string caption() override;

		std::string getNodeType() override;

	public:

		DEF_ARRAY_IN(Vec3f, Vertex, DeviceType::GPU, "");
		DEF_ARRAY_IN(Vec3f, Normal, DeviceType::GPU, "");
		DEF_ARRAY_IN(Vec2f, TexCoord, DeviceType::GPU, "");

		DEF_INSTANCES_IN(Shape, Shape, "");
		DEF_INSTANCES_IN(Material, Material, "");
		DEF_INSTANCES_IN(ShapeInstance, Instance, "");

	protected:
		void resetStates() override;
	};

	IMPLEMENT_TCLASS(GLInstanceVisualNode, TDataType)
};
