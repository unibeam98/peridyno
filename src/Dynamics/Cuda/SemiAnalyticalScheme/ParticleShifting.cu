#include "ParticleShifting.h"
#include "Node.h"
#include "SemiAnalyticalSummationDensity.h"
#include "Topology/NeighborPointQuery.h"
#include "IntersectionArea.h"

namespace dyno {

	__device__ inline Real KernSpikyGradient(const Real r, const Real h)
	{
		const Real q = r / h;
		if (q > 1.0f) return 0.0;
		else {
			const Real d = 1.0 - q;
			const Real hh = h * h;
			return -45.0f / ((Real)M_PI * hh*h) *d*d;
		}
	}

	template<typename Real>
	__device__ inline Real KernSpiky(const Real r, const Real h)
	{
		const Real q = r / h;
		if (q > 1.0f) return 0.0;
		else {
			const Real d = 1.0 - q;
			const Real hh = h * h;
			return -15.0f / ((Real)M_PI * hh*h) *d*d*d;
		}
	}

	template<typename Real>
	__device__ inline Real kernWeight1(const Real r, const Real h)
	{
		const Real q = r / h;
		if (q > 1.0f) return 0.0f;
		else {
			const Real d = 1.0f - q;
			const Real hh = h * h;
			return (1.0 - q * q*q*q)*h*h;
		}
	}


	template<typename Real>
	__device__ inline Real kernWRR1(const Real r, const Real h)
	{
		Real w = kernWeight1(r, h);
		const Real q = r / h;
		if (q < 0.5f)
		{
			return w / (0.25f*h*h);
		}
		return w / r / r;
	}



	template <typename Real, typename Coord>
	__global__ void PR_ComputeC_boundary(
		DArray<Coord> position,
		DArray<Coord> Adhesion,
		DArray<Real> totalW,
		DArray<Coord> TriDir,
		DArrayList<int> neighbors,
		DArrayList<int> neighborTri,
		DArray<Triangle> m_triangle_index,
		DArray<Coord> positionTri,
		Real smoothingLength,
		Real energyDepth)
	{
		int pId = threadIdx.x + (blockIdx.x * blockDim.x);
		if (pId >= position.size()) return;

		Coord pos_i = position[pId];
		Coord Tri_direction(0);//normal direction of boundaries��weighted sum of the triangle mesh norm��
		Coord numerator(0);

		List<int>& nbrIds_i = neighbors[pId];
		int nbSize = nbrIds_i.size();

		List<int>& nbrTriIds_i = neighborTri[pId];
		int nbSizeTri = nbrTriIds_i.size();
		

		Real AreaB;
		for (int ne = 0; ne < nbSizeTri; ne++)
		{
			int j = nbrTriIds_i[ne];

			Triangle3D t3d(positionTri[m_triangle_index[j][0]], positionTri[m_triangle_index[j][1]], positionTri[m_triangle_index[j][2]]);
			Plane3D PL(positionTri[m_triangle_index[j][0]], t3d.normal());//plane of Tri
			Point3D p3d(pos_i);

			Point3D nearest_pt = p3d.project(PL);
			Real r = (nearest_pt.origin - pos_i).norm();//distance between Fluid point and plane
			float d = p3d.distance(PL);

			Real AreaSum = calculateIntersectionArea(p3d, t3d, smoothingLength);
			Real MinDistance = abs(p3d.distance(t3d));
			Coord Min_Pt = (p3d.project(t3d)).origin - pos_i;
			
			
			Tri_direction += t3d.normal()*KernSpiky(MinDistance, smoothingLength);

			Coord boundNorm = t3d.normal();

			if (Min_Pt.norm() > 0)
				if (ne < nbSizeTri - 1)
				{
					int jn;
					do
					{
						jn = nbrTriIds_i[ne + 1];

						Triangle3D t3d_n(positionTri[m_triangle_index[jn][0]], positionTri[m_triangle_index[jn][1]], positionTri[m_triangle_index[jn][2]]);
						if ((t3d.normal().cross(t3d_n.normal())).norm() > EPSILON)// not at the same plane
						{
							break;
						}

						Real minDis = abs(p3d.distance(t3d_n));
						Coord minPt = (p3d.project(t3d_n)).origin - pos_i;

						AreaSum += calculateIntersectionArea(p3d, t3d_n, smoothingLength);

						if (abs(p3d.distance(t3d_n)) < MinDistance)
						{
							MinDistance = minDis;
							Min_Pt = minPt;

							Tri_direction += t3d_n.normal() * KernSpiky(MinDistance, smoothingLength);
						}


						ne++;
					} while (ne < nbSizeTri - 1);
				}
			
			Min_Pt /= Min_Pt.norm();

			
			d = abs(d);
			if (smoothingLength - d > EPSILON&& smoothingLength* smoothingLength - d * d > EPSILON&& d > EPSILON)
			{
				Coord n_PL = -t3d.normal();
				n_PL = n_PL / n_PL.norm();

				AreaB = M_PI * (smoothingLength * smoothingLength - d * d);//A0

				Real ep = 0.0001;
				Real weightS = ep*KernSpiky(r, smoothingLength);
				Real weightS_hat = ep* r*r*r* KernSpikyGradient(r, smoothingLength);
				
			
				Real EP_ij = - weightS * AreaSum;
				Real totalWeight = weightS_hat
					* 2.0 * (M_PI) * (1 - d / smoothingLength)//Omega_0
					* AreaSum * n_PL.dot(Min_Pt)//��n_s��d_n��*As
					/ AreaB;//A0

				
				numerator += EP_ij * boundNorm;
				totalW[pId] += totalWeight;//denominator

			}
		}
		
		if (Tri_direction.norm() > EPSILON)
		{
			Tri_direction /= Tri_direction.norm();
		}
		else  Tri_direction = Coord(0);

		TriDir[pId] = Tri_direction;
		Adhesion[pId] = numerator;
	}

	template <typename Real, typename Coord>
	__global__ void PR_ComputeGradient(
		DArray<Coord> grads,//delta Pos
		DArray<Coord> Adhesion,
		DArray<Real> totalW,//total weight from boundary mesh
		DArray<Real> rhoArr,//rDensity
		DArray<Coord> curPos,
		DArray<Coord> originPos,
		DArray<Attribute> attArr,
		DArrayList<int> neighbors,
		Real mass,
		Real h,
		Real inertia,
		Real bulk,
		Real surfaceTension,
		Real adhesion)
	{

		int pId = threadIdx.x + (blockIdx.x * blockDim.x);
		if (pId >= curPos.size()) return;
		if (!attArr[pId].isDynamic()) return;

		Real a1 = inertia;
		Real a2 = bulk;
		Real a3 = surfaceTension;
		Real a4 = adhesion;

		Real w1 = 1.0f*a1;
		Real w2 = 0.005f*(rhoArr[pId] - 1000.0f) / (1000.0f)*a2;
		if (w2 < EPSILON)
		{
			w2 = 0.0f;
		}
		Real w3 = 0.005f*a3;
		Real w4 =  a4;

		Coord pos_i = curPos[pId];

		Coord grad1_i = originPos[pId] - pos_i;

		Coord grad2(0);
		Real total_weight2 = 0.0f;
		Coord grad3(0);
		Real total_weight3 = 0.0f;
		Coord grad4(0);
		Real total_weight4(0);
		
		if (totalW.size() > 0)
			total_weight4 = totalW[pId];

		if (Adhesion[pId].norm() > 0 && Adhesion.size() > 0)
		{
			grad4 = Adhesion[pId];
		}

		List<int>& nbrIds_i = neighbors[pId];
		int nbSize = nbrIds_i.size();


		for (int ne = 0; ne < nbSize; ne++)
		{
			int j = nbrIds_i[ne];
			Coord pos_j = curPos[j];
			Real r = (pos_i - pos_j).norm();

			if (r > EPSILON)
			{
				Real weight2 = -mass * KernSpikyGradient(r, h);
				total_weight2 += weight2;
				Coord g2_ij = weight2 * (pos_i - pos_j) * (1.0f / r);
				grad2 += g2_ij;

				Real weight3 = kernWRR1(r, h);
				total_weight3 += weight3;
				Coord g3_ij = weight3 * (pos_i - pos_j)* (1.0f / r);
				grad3 += g3_ij;
			}
		}
		//printf("totalW: %f\n", total_weight4);
		total_weight2 = total_weight2 < EPSILON ? 1.0f : total_weight2;
		total_weight3 = total_weight3 < EPSILON ? 1.0f : total_weight3;
		total_weight4 = total_weight4 < EPSILON ? 1.0f : total_weight4;

		
		grad2 /= total_weight2;
		grad3 /= total_weight3;
		grad4 /= total_weight4;
		
		Coord nGrad3;
		if (grad3.norm() > EPSILON)
		{
			Real temp = grad3.norm();
			nGrad3 = grad3 / temp;
		}


		Real energy = grad3.dot(grad3);

		Coord nGrad4;
		//printf("gnorm: %f\n", grad4.norm());
		if (grad4.norm() > 0)
		{
			Real temp2 = grad4.norm();
			nGrad4 = grad4 / temp2;
		}

		Real energy_solid(0);
		if (grad4.norm() > 0)
			energy_solid = grad4.dot(grad4);


		for (int ne = 0; ne < nbSize; ne++)
		{
			int j = nbrIds_i[ne];
			Coord pos_j = curPos[j];
			Real r = (pos_i - pos_j).norm();

			if (r > EPSILON)
			{
				Real weight2 = -mass * KernSpikyGradient(r, h);
				Coord g2_ij = (weight2 / total_weight2)*(pos_i - pos_j) * (1.0f / r);
				atomicAdd(&grads[j][0], -w2 * g2_ij[0]);
				atomicAdd(&grads[j][1], -w2 * g2_ij[1]);
				atomicAdd(&grads[j][2], -w2 * g2_ij[2]);
			}
		}
		
		Coord shift4 = w4 * energy_solid*nGrad4;
		
		Real max_ax = abs(shift4[0]);
		if (abs(shift4[1]) > max_ax) max_ax = abs(shift4[1]);
		if (abs(shift4[2]) > max_ax) max_ax = abs(shift4[2]);

		Real threash = 0.00005;
		if (max_ax > threash)
			for (int i = 0; i < 3; ++i)
			{
				shift4[i] /= max_ax;
				shift4[i] *= threash;
			}
	
		atomicAdd(&grads[pId][0], w1*grad1_i[0] + w2 * grad2[0] - w3 * energy*nGrad3[0] - shift4[0]);
		atomicAdd(&grads[pId][1], w1*grad1_i[1] + w2 * grad2[1] - w3 * energy*nGrad3[1] - shift4[1]);
		atomicAdd(&grads[pId][2], w1*grad1_i[2] + w2 * grad2[2] - w3 * energy*nGrad3[2] - shift4[2]);
	}

	template <typename Coord>
	__global__ void PR_AddDPosition(
		DArray<Coord> grads,
		DArray<Coord> curPos,
		DArray<Attribute> attArr)
	{
		int pId = threadIdx.x + (blockIdx.x * blockDim.x);
		if (pId >= curPos.size()) return;
		if (!attArr[pId].isDynamic()) return;
		curPos[pId] += grads[pId];
	}

	template <typename Coord>
	__global__ void PR_UpdateVelocity(
		DArray<Coord> velArr,
		DArray<Coord> curArr,
		DArray<Coord> originArr,
		DArray<Attribute> attArr,
		DArray<Coord> TriDir,//normal of boundary
		float dt)
	{

		int pId = threadIdx.x + (blockIdx.x * blockDim.x);
		if (pId >= velArr.size()) return;

		if (attArr[pId].isDynamic())
		{
			Plane3D PL(curArr[pId], TriDir[pId]);
			Point3D origP(originArr[pId]);
			Point3D projectedP = origP.project(PL);
			Coord boundary_vec = projectedP.origin - curArr[pId];
			if (boundary_vec.norm() > 0)
				boundary_vec /= boundary_vec.norm();

			Real fr = 0.97f;//0.96f
			boundary_vec *= fr;
			boundary_vec[0] = 1.0f - abs(boundary_vec[0]);
			boundary_vec[1] = 1.0f - abs(boundary_vec[1]);
			boundary_vec[2] = 1.0f - abs(boundary_vec[2]);

			velArr[pId] += 1.0f*(curArr[pId] - originArr[pId]) / dt;

			//*********boundary friction part
			if (boundary_vec.norm() > 0) {
				if (abs(boundary_vec[0]) > fr)
					velArr[pId][0] *= boundary_vec[0];
				else
					velArr[pId][0] *= fr;
				if (abs(boundary_vec[1]) > fr)
					velArr[pId][1] *= boundary_vec[1];
				else
					velArr[pId][1] *= fr;
				if (abs(boundary_vec[2]) > fr)
					velArr[pId][2] *= boundary_vec[2];
				else
					velArr[pId][2] *= fr;

				//printf("boun_vec: %f, %f, %f,  dis: %f\n", boundary_vec[0], boundary_vec[1], boundary_vec[2], TriDis[pId]);
			}


		}
	}

	template<typename TDataType>
	ParticleShifting<TDataType>::ParticleShifting()
		: ParticleApproximation<TDataType>()
		, mIterationNumber(10)
		, mEnergyDepth(0.003)//0.003
	{
		this->varInertia()->setValue(Real(0.1));
		this->varBulk()->setValue(Real(0.5));
		this->inSmoothingLength()->setValue(Real(0.0125));//0.0125
		this->inSamplingDistance()->setValue(Real(0.005));

		mCalculateDensity = std::make_shared<SemiAnalyticalSummationDensity<TDataType>>();
		this->inSmoothingLength()->connect(mCalculateDensity->inSmoothingLength());
		inPosition()->connect(mCalculateDensity->inPosition());
		inNeighborIds()->connect(mCalculateDensity->inNeighborIds());
		inNeighborTriIds()->connect(mCalculateDensity->inNeighborTriIds());
		inTriangleInd()->connect(mCalculateDensity->inTriangleInd());
		inTriangleVer()->connect(mCalculateDensity->inTriangleVer());
		varRestDensity()->connect(mCalculateDensity->varRestDensity());

		mCalculateDensity->inSamplingDistance()->setValue(Real(0.005));

	};

	template<typename TDataType>
	ParticleShifting<TDataType>::~ParticleShifting()
	{
		mLambda.clear();
		mDeltaPos.clear();
		mPosBuf.clear();
	};

	template<typename TDataType>
	void ParticleShifting<TDataType>::compute()
	{
		Real dt = this->inTimeStep()->getData();

		int num = this->inPosition()->size();
		mLambda.resize(num);
		mDeltaPos.resize(num);
		mPosBuf.resize(num);
		mAdhesionEP.resize(num);
		mTotalW.resize(num);
		mBoundaryDir.resize(num);
		mBoundaryDis.resize(num);
		mAdhesionEP.reset();
		mTotalW.reset();
		mBoundaryDir.reset();
		mBoundaryDis.reset();

		Real d = mCalculateDensity->inSamplingDistance()->getData();
		Real rho_0 = mCalculateDensity->varRestDensity()->getData();
		Real mass = d * d*d*rho_0;

		mCalculateDensity->update();

		mPosBuf.assign(inPosition()->getData());

		int it = 0;
		while (it < mIterationNumber)
		{
			mDeltaPos.reset();

			mCalculateDensity->update();

			if (this->inNeighborTriIds()->getData().size() > 0) {

				cuExecute(num,
					PR_ComputeC_boundary,
					this->inPosition()->getData(),
					mAdhesionEP,
					mTotalW,
					mBoundaryDir,
					this->inNeighborIds()->getData(),
					this->inNeighborTriIds()->getData(),
					this->inTriangleInd()->getData(),
					this->inTriangleVer()->getData(),
					this->inSmoothingLength()->getData(),
					mEnergyDepth);
			}

			cuExecute(num,
				PR_ComputeGradient,
				mDeltaPos,
				mAdhesionEP,
				mTotalW,
				mCalculateDensity->outDensity()->getData(),
				this->inPosition()->getData(),
				mPosBuf,
				this->inAttribute()->getData(),
				this->inNeighborIds()->getData(),
				mass,
				this->inSmoothingLength()->getData(),
				this->varInertia()->getData(),
				this->varBulk()->getData(),
				this->varSurfaceTension()->getData(),
				this->varAdhesionIntensity()->getData());

			cuExecute(num,
				PR_AddDPosition,
				mDeltaPos,
				this->inPosition()->getData(),
				this->inAttribute()->getData());

			it++;
		}

		cuExecute(num,
			PR_UpdateVelocity,
			this->inVelocity()->getData(),
			this->inPosition()->getData(),
			mPosBuf,
			this->inAttribute()->getData(),
			mBoundaryDir,
			dt);

	};

	DEFINE_CLASS(ParticleShifting);
}