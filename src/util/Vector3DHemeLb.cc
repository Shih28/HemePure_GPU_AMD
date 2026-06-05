
// This file is part of HemeLB and is Copyright (C)
// the HemeLB team and/or their institutions, as detailed in the
// file AUTHORS. This software is provided under the terms of the
// license in the file LICENSE.

#include "util/Vector3D.h"
#include "net/mpi.h"
#include "Exception.h"

namespace hemelb
{
  namespace net
  {
    template<typename vectorType>
    MPI_Datatype GenerateTypeForVector()
    {
      const int typeCount = 1;
      int blocklengths[typeCount] = { 3 };

      MPI_Datatype types[typeCount] = { net::MpiDataType<vectorType>() };

      MPI_Aint displacements[typeCount] = { 0 };

      MPI_Datatype ret;

      HEMELB_MPI_CALL(
          MPI_Type_create_struct,
          (typeCount, blocklengths, displacements, types, &ret)
      );

      HEMELB_MPI_CALL(MPI_Type_commit, (&ret));
      return ret;
    }
    template<>
    MPI_Datatype MpiDataTypeTraits<hemelb::util::Vector3D<float> >::RegisterMpiDataType()
    {
      return GenerateTypeForVector<float> ();
    }

    template<>
    MPI_Datatype MpiDataTypeTraits<hemelb::util::Vector3D<site_t> >::RegisterMpiDataType()
    {
      return GenerateTypeForVector<site_t> ();
    }

    // Vector3D<distribn_t> is now the same type as Vector3D<float> (distribn_t
    // is float), so its instantiation lives in the Vector3D<float> one above.
    // We still need Vector3D<double> for the physical-precision vectors
    // (traction, wall normals, forces, positions, ...).
    template<>
    MPI_Datatype MpiDataTypeTraits<hemelb::util::Vector3D<double> >::RegisterMpiDataType()
    {
      return GenerateTypeForVector<double> ();
    }
  }
  namespace util
  {
    namespace
    {
      void DefaultHandlerFunction(int direction)
      {
        // TODO need to find a way of handling this case better.
        throw Exception() << "Failed while accessing a direction in Vector3D.";
      }
    }
    Vector3DBase::HandlerFunction* Vector3DBase::handler = DefaultHandlerFunction;

  }
}
