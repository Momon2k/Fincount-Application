// pages/api/sessions/index.js or app/api/sessions/route.js
import jwt from 'jsonwebtoken';

// Mock database - replace with your actual database
let sessions = [];

// Middleware to verify JWT token
function verifyToken(req) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw new Error('No token provided');
  }

  const token = authHeader.substring(7);
  try {
    return jwt.verify(token, process.env.JWT_SECRET || 'your-secret-key');
  } catch (error) {
    throw new Error('Invalid token');
  }
}

export default async function handler(req, res) {
  try {
    // Verify authentication
    const decoded = verifyToken(req);
    const userId = decoded.userId;

    if (req.method === 'GET') {
      // Get all sessions for the authenticated user
      const userSessions = sessions.filter(session => session.userId === userId);
      res.status(200).json(userSessions);
    } else if (req.method === 'POST') {
      // Create a new session
      const {
        id,
        batchId,
        species,
        location,
        notes,
        counts,
        timestamp,
        imageUrl
      } = req.body;

      if (!id || !batchId || !species || !location || !counts || !timestamp) {
        return res.status(400).json({ message: 'Missing required fields' });
      }

      const newSession = {
        id,
        userId,
        batchId,
        species,
        location,
        notes: notes || '',
        counts,
        timestamp,
        imageUrl: imageUrl || '',
        createdAt: new Date().toISOString()
      };

      sessions.push(newSession);
      res.status(201).json(newSession);
    } else {
      res.status(405).json({ message: 'Method not allowed' });
    }
  } catch (error) {
    console.error('Sessions API error:', error);
    if (error.message === 'No token provided' || error.message === 'Invalid token') {
      res.status(401).json({ message: 'Unauthorized' });
    } else {
      res.status(500).json({ message: 'Internal server error' });
    }
  }
}

// For App Router (Next.js 13+), use this format instead:
/*
export async function GET(request) {
  try {
    const decoded = verifyTokenFromRequest(request);
    const userId = decoded.userId;

    const userSessions = sessions.filter(session => session.userId === userId);
    return Response.json(userSessions);
  } catch (error) {
    console.error('Sessions GET error:', error);
    if (error.message === 'No token provided' || error.message === 'Invalid token') {
      return Response.json({ message: 'Unauthorized' }, { status: 401 });
    } else {
      return Response.json({ message: 'Internal server error' }, { status: 500 });
    }
  }
}

export async function POST(request) {
  try {
    const decoded = verifyTokenFromRequest(request);
    const userId = decoded.userId;

    const body = await request.json();
    const {
      id,
      batchId,
      species,
      location,
      notes,
      counts,
      timestamp,
      imageUrl
    } = body;

    if (!id || !batchId || !species || !location || !counts || !timestamp) {
      return Response.json({ message: 'Missing required fields' }, { status: 400 });
    }

    const newSession = {
      id,
      userId,
      batchId,
      species,
      location,
      notes: notes || '',
      counts,
      timestamp,
      imageUrl: imageUrl || '',
      createdAt: new Date().toISOString()
    };

    sessions.push(newSession);
    return Response.json(newSession, { status: 201 });
  } catch (error) {
    console.error('Sessions POST error:', error);
    if (error.message === 'No token provided' || error.message === 'Invalid token') {
      return Response.json({ message: 'Unauthorized' }, { status: 401 });
    } else {
      return Response.json({ message: 'Internal server error' }, { status: 500 });
    }
  }
}

function verifyTokenFromRequest(request) {
  const authHeader = request.headers.get('authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw new Error('No token provided');
  }

  const token = authHeader.substring(7);
  try {
    return jwt.verify(token, process.env.JWT_SECRET || 'your-secret-key');
  } catch (error) {
    throw new Error('Invalid token');
  }
}
*/
